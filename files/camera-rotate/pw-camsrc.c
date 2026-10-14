/* pw-camsrc: publish raw YUY2 frames read from stdin as a PipeWire camera.
 *
 *   pw-camsrc WIDTH HEIGHT FPS NODE_NAME "DESCRIPTION" < frames
 *
 * Each frame is WIDTH*HEIGHT*2 bytes. The node is a Video/Source with media.role Camera, so
 * the camera portal (Snapshot, Firefox) lists it. It offers one shape, WIDTHxHEIGHT or that
 * turned on its side, as SIGUSR1 (portrait) / SIGUSR2 (landscape) last asked, so an app
 * opening the camera gets the screen's shape. One at a time: apps link more than once (preview
 * plus a probe) and two links on different shapes made Snapshot read past a frame and crash.
 * On stdout: "ready" once the signals are handled, "size W H" when an app picks a shape, "start" / "stop" when it starts or stops
 * watching, so the frame producer only needs the camera while it's in use.
 * Needed because GStreamer's pipewiresink can't offer a source node on PipeWire 1.0 and
 * PipeWire can't negotiate with v4l2loopback.
 * Based on PipeWire's src/examples/video-src.c.
 *
 * build: gcc -O2 -o pw-camsrc pw-camsrc.c $(pkg-config --cflags --libs libpipewire-0.3) -lpthread
 */
#define _GNU_SOURCE   /* memfd_create */
#include <errno.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#include <spa/param/video/format-utils.h>
#include <spa/param/buffers.h>
#include <pipewire/pipewire.h>

struct data {
	struct pw_main_loop *loop;
	struct pw_stream *stream;
	struct spa_source *timer;
	int width, height, fps;  /* the negotiated shape */
	int land_w, land_h;      /* the landscape shape */
	int portrait;            /* list the portrait shape first */
	int linked;              /* an app holds a format, even paused: keep the shape it picked */
	uint64_t seq;
	size_t frame_size;
	uint8_t *latest;       /* newest frame from stdin */
	int have_frame;
	pthread_mutex_t lock;
};

static void update_formats(struct data *d);

static void *reader(void *arg)
{
	struct data *d = arg;
	uint8_t *buf = malloc(d->frame_size);
	for (;;) {
		size_t got = 0;
		while (got < d->frame_size) {
			ssize_t n = read(0, buf + got, d->frame_size - got);
			if (n <= 0)     /* input ended (the camera side stopped): the node goes too */
				exit(0);
			got += n;
		}
		pthread_mutex_lock(&d->lock);
		memcpy(d->latest, buf, d->frame_size);
		d->have_frame = 1;
		pthread_mutex_unlock(&d->lock);
	}
}

static void on_process(void *userdata)
{
	struct data *d = userdata;
	struct pw_buffer *b = pw_stream_dequeue_buffer(d->stream);
	if (!b)
		return;
	struct spa_buffer *buf = b->buffer;
	uint8_t *p = buf->datas[0].data;
	if (!p)
		return;
	size_t n = SPA_MIN(d->frame_size, (size_t)buf->datas[0].maxsize);
	pthread_mutex_lock(&d->lock);
	if (d->have_frame)
		memcpy(p, d->latest, n);
	else
		memset(p, 0x80, n);   /* grey until the first frame */
	pthread_mutex_unlock(&d->lock);
	struct spa_meta_header *h = spa_buffer_find_meta_data(buf, SPA_META_Header, sizeof(*h));
	if (h) {   /* timestamps: without them every frame looked the same age to the app */
		struct timespec now;
		clock_gettime(CLOCK_MONOTONIC, &now);
		h->pts = SPA_TIMESPEC_TO_NSEC(&now);
		h->flags = 0;
		h->seq = d->seq++;
		h->dts_offset = 0;
	}
	buf->datas[0].chunk->offset = 0;
	buf->datas[0].chunk->size = n;
	buf->datas[0].chunk->stride = d->width * 2;
	pw_stream_queue_buffer(d->stream, b);
}

static void on_timeout(void *userdata, uint64_t expirations)
{
	struct data *d = userdata;
	pw_stream_trigger_process(d->stream);
}

static void on_state_changed(void *userdata, enum pw_stream_state old,
			     enum pw_stream_state state, const char *error)
{
	struct data *d = userdata;
	struct timespec value = {0}, interval = {0};
	if (state == PW_STREAM_STATE_STREAMING) {
		value.tv_nsec = 1;
		interval.tv_nsec = 1000000000L / d->fps;
		printf("start\n");
	} else if (old == PW_STREAM_STATE_STREAMING) {
		pthread_mutex_lock(&d->lock);
		d->have_frame = 0;      /* grey, not a stale picture, next time */
		pthread_mutex_unlock(&d->lock);
		printf("stop\n");
	}
	fflush(stdout);
	if (state == PW_STREAM_STATE_ERROR) {
		/* the node is unusable from here; surface-camera-rotate starts a fresh one */
		fprintf(stderr, "pw-camsrc: stream error: %s\n", error ? error : "?");
		exit(1);
	}
	/* run the clock only while someone is watching */
	pw_loop_update_timer(pw_main_loop_get_loop(d->loop), d->timer, &value, &interval, false);
}

static void on_param_changed(void *userdata, uint32_t id, const struct spa_pod *param)
{
	struct data *d = userdata;
	uint8_t buffer[1024];
	struct spa_pod_builder b = SPA_POD_BUILDER_INIT(buffer, sizeof(buffer));
	struct spa_video_info_raw info;
	if (id != SPA_PARAM_Format)
		return;
	if (param == NULL) {        /* the last app let go */
		d->linked = 0;
		update_formats(d);      /* catch up with a turn made while it was linked */
		return;
	}
	if (spa_format_video_raw_parse(param, &info) < 0)
		return;
	d->linked = 1;
	pthread_mutex_lock(&d->lock);
	d->width = info.size.width;   /* both shapes have the same frame size */
	d->height = info.size.height;
	pthread_mutex_unlock(&d->lock);
	printf("size %d %d\n", d->width, d->height);
	fflush(stdout);
	const struct spa_pod *params[2];
	params[0] = spa_pod_builder_add_object(&b,
		SPA_TYPE_OBJECT_ParamBuffers, SPA_PARAM_Buffers,
		SPA_PARAM_BUFFERS_buffers, SPA_POD_CHOICE_RANGE_Int(8, 4, 16),
		SPA_PARAM_BUFFERS_blocks,  SPA_POD_Int(1),
		SPA_PARAM_BUFFERS_size,    SPA_POD_Int((int)d->frame_size),
		SPA_PARAM_BUFFERS_stride,  SPA_POD_Int(d->width * 2),
		SPA_PARAM_BUFFERS_dataType, SPA_POD_CHOICE_FLAGS_Int(1 << SPA_DATA_MemFd));  /* see on_add_buffer */
	params[1] = spa_pod_builder_add_object(&b,
		SPA_TYPE_OBJECT_ParamMeta, SPA_PARAM_Meta,
		SPA_PARAM_META_type, SPA_POD_Id(SPA_META_Header),
		SPA_PARAM_META_size, SPA_POD_Int(sizeof(struct spa_meta_header)));
	pw_stream_update_params(d->stream, params, 2);
}

/* Our own buffers, one memfd each. PipeWire's would reach the app as pointers into a shared
 * block, which it unmaps whenever an app links or unlinks (Snapshot does that a few times on
 * start) while the app may still hold frames: Snapshot crashed reading them. An app keeps
 * its own reference to a memfd, so its frames stay valid. */
static void on_add_buffer(void *userdata, struct pw_buffer *b)
{
	struct data *d = userdata;
	struct spa_data *sd = &b->buffer->datas[0];
	int fd = memfd_create("pw-camsrc", MFD_CLOEXEC | MFD_ALLOW_SEALING);
	if (fd < 0 || ftruncate(fd, d->frame_size) < 0) {
		fprintf(stderr, "pw-camsrc: memfd: %m\n");
		if (fd >= 0)
			close(fd);
		return;
	}
	void *p = mmap(NULL, d->frame_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (p == MAP_FAILED) {
		fprintf(stderr, "pw-camsrc: mmap: %m\n");
		close(fd);
		return;
	}
	sd->type = SPA_DATA_MemFd;
	sd->flags = SPA_DATA_FLAG_READWRITE;
	sd->fd = fd;
	sd->mapoffset = 0;
	sd->maxsize = d->frame_size;
	sd->data = p;
}

static void on_remove_buffer(void *userdata, struct pw_buffer *b)
{
	struct data *d = userdata;
	struct spa_data *sd = &b->buffer->datas[0];
	if (sd->data)
		munmap(sd->data, d->frame_size);
	if (sd->fd >= 0)
		close(sd->fd);
	sd->data = NULL;
	sd->fd = -1;
}

static const struct pw_stream_events stream_events = {
	PW_VERSION_STREAM_EVENTS,
	.add_buffer = on_add_buffer,
	.remove_buffer = on_remove_buffer,
	.process = on_process,
	.state_changed = on_state_changed,
	.param_changed = on_param_changed,
};

/* the screen's shape */
static const struct spa_pod *build_format(struct data *d, struct spa_pod_builder *bp)
{
	struct spa_rectangle r = d->portrait ? SPA_RECTANGLE(d->land_h, d->land_w)
					     : SPA_RECTANGLE(d->land_w, d->land_h);
	return spa_pod_builder_add_object(bp,
		SPA_TYPE_OBJECT_Format, SPA_PARAM_EnumFormat,
		SPA_FORMAT_mediaType,       SPA_POD_Id(SPA_MEDIA_TYPE_video),
		SPA_FORMAT_mediaSubtype,    SPA_POD_Id(SPA_MEDIA_SUBTYPE_raw),
		SPA_FORMAT_VIDEO_format,    SPA_POD_Id(SPA_VIDEO_FORMAT_YUY2),
		SPA_FORMAT_VIDEO_size,      SPA_POD_Rectangle(&r),
		SPA_FORMAT_VIDEO_framerate, SPA_POD_Fraction(&SPA_FRACTION(d->fps, 1)));
}

static void update_formats(struct data *d)
{
	uint8_t buffer[1024];
	struct spa_pod_builder b = SPA_POD_BUILDER_INIT(buffer, sizeof(buffer));
	const struct spa_pod *params[1] = { build_format(d, &b) };
	pw_stream_update_params(d->stream, params, 1);
}

static void on_shape(void *userdata, int signal_number)
{
	struct data *d = userdata;
	int portrait = signal_number == SIGUSR1;
	if (portrait != d->portrait) {
		d->portrait = portrait;
		/* an app linked to the old shape (even paused) can't follow: wait till it lets go */
		if (!d->linked)
			update_formats(d);
	}
}

static void do_quit(void *userdata, int signal_number)
{
	struct data *d = userdata;
	pw_main_loop_quit(d->loop);
}

int main(int argc, char *argv[])
{
	struct data d = { 0 };
	if (argc != 6) {
		fprintf(stderr, "usage: %s WIDTH HEIGHT FPS NODE_NAME DESCRIPTION < yuy2-frames\n", argv[0]);
		return 2;
	}
	d.width = d.land_w = atoi(argv[1]);
	d.height = d.land_h = atoi(argv[2]);
	d.fps = atoi(argv[3]);
	d.frame_size = (size_t)d.width * d.height * 2;
	d.latest = malloc(d.frame_size);
	pthread_mutex_init(&d.lock, NULL);

	pw_init(&argc, &argv);
	d.loop = pw_main_loop_new(NULL);
	struct pw_loop *l = pw_main_loop_get_loop(d.loop);
	pw_loop_add_signal(l, SIGINT, do_quit, &d);
	pw_loop_add_signal(l, SIGTERM, do_quit, &d);
	pw_loop_add_signal(l, SIGUSR1, on_shape, &d);
	pw_loop_add_signal(l, SIGUSR2, on_shape, &d);
	d.timer = pw_loop_add_timer(l, on_timeout, &d);

	d.stream = pw_stream_new_simple(l, argv[4],
		pw_properties_new(
			PW_KEY_MEDIA_CLASS, "Video/Source",
			PW_KEY_MEDIA_TYPE, "Video",
			PW_KEY_MEDIA_CATEGORY, "Capture",
			PW_KEY_MEDIA_ROLE, "Camera",
			PW_KEY_NODE_NAME, argv[4],
			PW_KEY_NODE_DESCRIPTION, argv[5],
			NULL),
		&stream_events, &d);

	uint8_t buffer[1024];
	struct spa_pod_builder b = SPA_POD_BUILDER_INIT(buffer, sizeof(buffer));
	const struct spa_pod *params[1] = { build_format(&d, &b) };
	pw_stream_connect(d.stream, PW_DIRECTION_OUTPUT, PW_ID_ANY,
		PW_STREAM_FLAG_DRIVER | PW_STREAM_FLAG_ALLOC_BUFFERS, params, 1);
	printf("ready\n");     /* SIGUSR1/2 are handled from here on */
	fflush(stdout);

	pthread_t t;
	pthread_create(&t, NULL, reader, &d);
	pw_main_loop_run(d.loop);

	pw_stream_destroy(d.stream);
	pw_main_loop_destroy(d.loop);
	pw_deinit();
	return 0;
}
