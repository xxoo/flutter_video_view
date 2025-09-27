#include "include/video_view/video_view_plugin.h"
#include <ctype.h>
#include <locale.h>
#include <gdk/gdkx.h>
#include <gdk/gdkwayland.h>
#include <gtk/gtk.h>
#include <epoxy/egl.h>
#include <epoxy/glx.h>
#include <mpv/client.h>
#include <mpv/render_gl.h>
#include <unicode/uloc.h>

/* player definitions */

typedef struct {
	FlTextureGL parent_instance;
	mpv_opengl_fbo fbo;
	mpv_handle* mpv;
	mpv_render_context* mpvRenderContext;
	FlEventChannel* eventChannel;
	gchar* source;
	int64_t id;
	int64_t position;
	int64_t bufferPosition;
	double speed;
	double volume;
	gchar* preferredAudioLanguage;
	gchar* preferredSubtitleLanguage;
	GArray* videoTracks; // video tracks with id, width, height, bitrate
	GArray* audioTracks; // audio tracks with id, language
	GArray* subtitleTracks; // subtitle tracks with id, language
	GLuint texture;
	GLsizei width;
	GLsizei height;
	guint inhibit_cookie;
	uint32_t maxBitRate; // 0 for auto
	uint16_t maxWidth;
	uint16_t maxHeight;
	uint16_t overrideAudio; // 0 for auto otherwise track id
	uint16_t overrideSubtitle;
	uint8_t state; // 0: idle, 1: opening, 2: paused, 3: playing
	bool looping;
	bool streaming;
	bool networking;
	bool seeking;
	bool keepScreenOn;
} VideoViewPlugin;
#define VIDEO_VIEW_PLUGIN(obj) (G_TYPE_CHECK_INSTANCE_CAST((obj), video_view_plugin_get_type(), VideoViewPlugin))
typedef struct {
	FlTextureGLClass parent_class;
} VideoViewPluginClass;
G_DEFINE_TYPE(VideoViewPlugin, video_view_plugin, fl_texture_gl_get_type())

/* plugin definitions */

static GTree* players; // all write operations on the tree are done in the main thread
static GMutex mutex;   // so we just need to lock the mutex when reading in other threads
static FlBinaryMessenger* messenger;
static FlTextureRegistrar* textureRegistrar;
static FlMethodCodec* codec;
static FlMethodChannel* methodChannel;

/* player implementation */

typedef struct {
	uint16_t id;
	uint16_t width;
	uint16_t height;
	uint32_t bitrate;
} VideoViewPluginVideoTrack;

typedef struct {
	uint16_t id;
	uint8_t size;
	bool def;
	gchar* language[3];
} VideoViewPluginTrack;

static void video_view_plugin_track_free(void* item) {
	const VideoViewPluginTrack* track = item;
	g_free(track->language[0]);
}

static gboolean video_view_plugin_is_eof(const VideoViewPlugin* self) {
	gboolean eof;
	mpv_get_property(self->mpv, "eof-reached", MPV_FORMAT_FLAG, &eof);
	return eof;
}

static int64_t video_view_plugin_get_pos(const VideoViewPlugin* self) {
	double pos;
	mpv_get_property(self->mpv, "time-pos/full", MPV_FORMAT_DOUBLE, &pos);
	return (int64_t)(pos * 1000);
}

static void video_view_plugin_set_pause(const VideoViewPlugin* self, gboolean pause) {
	mpv_set_property(self->mpv, "pause", MPV_FORMAT_FLAG, &pause);
}

static void video_view_plugin_just_seek_to(VideoViewPlugin* self, const int64_t position, const bool fast, const bool setstate) {
	gchar* t = g_strdup_printf("%lf", (double)position / 1000);
	const gchar* cmd[] = { "seek", t, fast ? "absolute+keyframes" : "absolute", NULL };
	mpv_command(self->mpv, cmd);
	g_free(t);
	if (setstate) {
		self->seeking = true;
	}
}

static uint8_t video_view_plugin_split_lang(const gchar* lang, gchar* result[3]) {
	uint8_t count = 0;
	uint8_t start = 0;
	uint8_t pos1 = 0;
	uint8_t pos2 = 0;
	while (lang[pos1] == '_' || lang[pos1] == '-' || lang[pos1] == '.') {
		pos1++;
	}
	gchar* str = g_malloc(MIN(strlen(lang) - pos1 + 1, UINT8_MAX));
	while (count < 3) {
		const bool end = pos1 == UINT8_MAX || !lang[pos1] || lang[pos1] == '.';
		if (end || lang[pos1] == '_' || lang[pos1] == '-') {
			str[pos2] = 0;
			if (pos2 > start) {
				result[count++] = &str[start];
				start = pos2 + 1;
			}
			if (end) {
				break;
			}
		} else {
			str[pos2] = tolower(lang[pos1]);
		}
		pos1++;
		pos2++;
	}
	return count;
}

static uint16_t video_view_plugin_match_lang(const GArray* lang) {
	uint8_t count = 3;
	uint16_t j = 0;
	for (guint i = 0; i < lang->len; i++) {
		const VideoViewPluginTrack* t = g_array_index(lang, VideoViewPluginTrack*, i);
		if (t->size < count || (t->size == count && t->def)) {
			j = t->id;
			count = t->size;
		}
	}
	return j;
}

static uint16_t video_view_plugin_find_lang(const GArray* lang1, const GArray* lang2) {
	uint16_t i = video_view_plugin_match_lang(lang2);
	if (i == 0) {
		i = video_view_plugin_match_lang(lang1);
	}
	return i;
}

static void video_view_plugin_set_default_track(const VideoViewPlugin* self, const uint8_t type) {
	if (self->state > 1) {
		gchar* language = type ? self->preferredSubtitleLanguage : self->preferredAudioLanguage;
		if (!language) {
			language = setlocale(LC_CTYPE, NULL);
		}
		const GArray* tracks = type ? self->subtitleTracks : self->audioTracks;
		VideoViewPluginTrack t = { 0 };
		t.size = video_view_plugin_split_lang(language, t.language);
		GArray* lang1 = g_array_new(FALSE, FALSE, sizeof(VideoViewPluginTrack*));
		GArray* lang2 = g_array_new(FALSE, FALSE, sizeof(VideoViewPluginTrack*));
		uint16_t def = 0;
		for (guint i = 0; i < tracks->len; i++) {
			VideoViewPluginTrack* track = &g_array_index(tracks, VideoViewPluginTrack, i);
			if (!def || track->def) {
				def = track->id;
			}
			if (g_strcmp0(t.language[0], track->language[0]) == 0) {
				g_array_append_val(lang1, track);
				if (t.size > 1 && track->size > 1 && g_strcmp0(t.language[1], track->language[1]) == 0) {
					g_array_append_val(lang2, track);
					if (t.size > 2 && track->size > 2 && g_strcmp0(t.language[2], track->language[2]) == 0) {
						t.id = track->id;
						break;
					}
				}
			}
		}
		if (!t.id) {
			t.id = video_view_plugin_find_lang(lang1, lang2);
			if (!t.id && def) {
				t.id = def;
			}
		}
		video_view_plugin_track_free(&t);
		g_array_free(lang1, TRUE);
		g_array_free(lang2, TRUE);
		gchar* p = g_strdup_printf("%d", t.id);
		mpv_set_property_string(self->mpv, type ? "sid" : "aid", p);
		g_free(p);
	}
}

static void video_view_plugin_set_max_size(VideoViewPlugin* self) {
	int64_t oldId;
	double pos;
	mpv_get_property(self->mpv, "vid", MPV_FORMAT_INT64, &oldId);
	mpv_get_property(self->mpv, "time-pos/full", MPV_FORMAT_DOUBLE, &pos);
	if (self->maxWidth > 0 || self->maxHeight > 0) {
		uint16_t id = 0;
		uint16_t maxWidth = 0;
		uint16_t maxHeight = 0;
		uint16_t minWidth = UINT16_MAX;
		uint16_t minHeight = UINT16_MAX;
		uint32_t maxBitrate = 0;
		uint32_t minBitrate = UINT32_MAX;
		uint16_t minId = 0;
		for (uint i = 0; i < self->videoTracks->len; i++) {
			const VideoViewPluginVideoTrack* data = &g_array_index(self->videoTracks, VideoViewPluginVideoTrack, i);
			if ((self->maxWidth == 0 || data->width <= self->maxWidth) && (self->maxHeight == 0 || data->height <= self->maxHeight) && (self->maxBitRate == 0 || data->bitrate <= self->maxBitRate) && data->width > maxWidth && data->height > maxHeight && data->bitrate > maxBitrate) {
				id = data->id;
				maxWidth = data->width;
				maxHeight = data->height;
				maxBitrate = data->bitrate;
			}
			if (id == 0 && data->width < minWidth && data->height < minHeight && data->bitrate < minBitrate) {
				minId = data->id;
				minWidth = data->width;
				minHeight = data->height;
				minBitrate = data->bitrate;
			}
		}
		if (id == 0) {
			id = minId;
		}
		if (id != 0 && id != oldId) {
			gchar* p = g_strdup_printf("%d", id);
			mpv_set_property_string(self->mpv, "vid", p);
			g_free(p);
		}
	} else {
		mpv_set_property_string(self->mpv, "vid", "auto");
	}
	int64_t newId;
	mpv_get_property(self->mpv, "vid", MPV_FORMAT_INT64, &newId);
	if (newId != oldId) {
		video_view_plugin_just_seek_to(self, (int64_t)(pos * 1000), true, false);
	}
}

static void video_view_plugin_send_time(const VideoViewPlugin* self, int64_t pos) {
	g_autoptr(FlValue) evt = fl_value_new_map();
	fl_value_set_string_take(evt, "event", fl_value_new_string("position"));
	fl_value_set_string_take(evt, "value", fl_value_new_int(pos));
	fl_event_channel_send(self->eventChannel, evt, NULL, NULL);
}

static void video_view_plugin_send_buffer(const VideoViewPlugin* self, int64_t pos) {
	g_autoptr(FlValue) evt = fl_value_new_map();
	fl_value_set_string_take(evt, "event", fl_value_new_string("buffer"));
	fl_value_set_string_take(evt, "start", fl_value_new_int(pos));
	fl_value_set_string_take(evt, "end", fl_value_new_int(self->bufferPosition));
	fl_event_channel_send(self->eventChannel, evt, NULL, NULL);
}

static void video_view_plugin_set_inhibit(VideoViewPlugin* self, const bool enable) {
	if (enable && self->inhibit_cookie != 0 || !enable && self->inhibit_cookie == 0) {
		return;
	}
	GApplication* app = g_application_get_default();
	if (!app || !GTK_IS_APPLICATION(app)) {
		return;
	}
	GtkApplication* gtkApp = GTK_APPLICATION(app);
	if (enable) {
		self->inhibit_cookie = gtk_application_inhibit(gtkApp, gtk_application_get_active_window(gtkApp), GTK_APPLICATION_INHIBIT_IDLE, "VideoViewPlugin");
	} else {
		gtk_application_uninhibit(gtkApp, self->inhibit_cookie);
		self->inhibit_cookie = 0;
	}
}

static void video_view_plugin_loaded(VideoViewPlugin* self) {
	int64_t count;
	mpv_get_property(self->mpv, "track-list/count", MPV_FORMAT_INT64, &count);
	FlValue* audioTracks = fl_value_new_map();
	FlValue* subtitleTracks = fl_value_new_map();
	for (uint i = 0; i < count; i++) {
		gchar* str;
		gchar p[33];
		sprintf(p, "track-list/%d/type", i);
		mpv_get_property(self->mpv, p, MPV_FORMAT_STRING, &str);
		const uint8_t type = g_str_equal(str, "video") ? 2 : g_str_equal(str, "audio") ? 0 : 1;
		mpv_free(str);
		int64_t trackId;
		sprintf(p, "track-list/%d/id", i);
		mpv_get_property(self->mpv, p, MPV_FORMAT_INT64, &trackId);
		int64_t size;
		if (type == 2) {
			VideoViewPluginVideoTrack data = { .id = (uint16_t)trackId };
			sprintf(p, "track-list/%d/demux-w", i);
			if (!mpv_get_property(self->mpv, p, MPV_FORMAT_INT64, &size)) {
				data.width = (uint16_t)size;
			}
			sprintf(p, "track-list/%d/demux-h", i);
			if (!mpv_get_property(self->mpv, p, MPV_FORMAT_INT64, &size)) {
				data.height = (uint16_t)size;
			}
			sprintf(p, "track-list/%d/hls-bitrate", i);
			if (!mpv_get_property(self->mpv, p, MPV_FORMAT_INT64, &size)) {
				data.bitrate = (uint32_t)size;
			}
			g_array_append_val(self->videoTracks, data);
		} else {
			VideoViewPluginTrack t = { .id = (uint16_t)trackId };
			sprintf(p, "track-list/%d/default", i);
			if (!mpv_get_property(self->mpv, p, MPV_FORMAT_STRING, &str)) {
				t.def = g_str_equal(str, "yes");
				mpv_free(str);
			}
			FlValue* info = fl_value_new_map();
			sprintf(p, "track-list/%d/lang", i);
			if (!mpv_get_property(self->mpv, p, MPV_FORMAT_STRING, &str)) {
				UErrorCode status = U_ZERO_ERROR;
				char langtag[ULOC_FULLNAME_CAPACITY];
				uloc_toLanguageTag(str, langtag, ULOC_FULLNAME_CAPACITY, FALSE, &status); // we don't want ISO 639-2 codes
				const gchar* lang = U_FAILURE(status) ? str : langtag;
				fl_value_set_string_take(info, "language", fl_value_new_string(lang));
				t.size = video_view_plugin_split_lang(lang, t.language);
				mpv_free(str);
			}
			g_array_append_val(type ? self->subtitleTracks : self->audioTracks, t);
			sprintf(p, "track-list/%d/title", i);
			if (!mpv_get_property(self->mpv, p, MPV_FORMAT_STRING, &str)) {
				fl_value_set_string_take(info, "label", fl_value_new_string(str));
				mpv_free(str);
			}
			sprintf(p, "track-list/%d/codec", i);
			if (!mpv_get_property(self->mpv, p, MPV_FORMAT_STRING, &str)) {
				fl_value_set_string_take(info, "format", fl_value_new_string(str));
				mpv_free(str);
			} else {
				sprintf(p, "track-list/%d/format-name", i);
				if (!mpv_get_property(self->mpv, p, MPV_FORMAT_STRING, &str)) {
					fl_value_set_string_take(info, "format", fl_value_new_string(str));
					mpv_free(str);
				}
			}
			if (type) {
				sprintf(p, "%d.%ld", type, trackId);
				fl_value_set_string_take(subtitleTracks, p, info);
			} else {
				sprintf(p, "track-list/%d/demux-bitrate", i);
				if (!mpv_get_property(self->mpv, p, MPV_FORMAT_INT64, &size)) {
					fl_value_set_string_take(info, "bitrate", fl_value_new_int(size));
				}
				sprintf(p, "track-list/%d/demux-channel-count", i);
				if (!mpv_get_property(self->mpv, p, MPV_FORMAT_INT64, &size)) {
					fl_value_set_string_take(info, "channels", fl_value_new_int(size));
				}
				sprintf(p, "track-list/%d/demux-samplerate", i);
				if (!mpv_get_property(self->mpv, p, MPV_FORMAT_INT64, &size)) {
					fl_value_set_string_take(info, "sampleRate", fl_value_new_int(size));
				}
				sprintf(p, "%d.%ld", type, trackId);
				fl_value_set_string_take(audioTracks, p, info);
			}
		}
	}
	double duration;
	if (self->streaming) {
		duration = 0;
	} else {
		mpv_get_property(self->mpv, "duration/full", MPV_FORMAT_DOUBLE, &duration);
	}
	self->state = 2;
	video_view_plugin_set_max_size(self);
	video_view_plugin_set_default_track(self, 0);
	video_view_plugin_set_default_track(self, 1);
	g_autoptr(FlValue) evt = fl_value_new_map();
	fl_value_set_string_take(evt, "event", fl_value_new_string("mediaInfo"));
	fl_value_set_string_take(evt, "source", fl_value_new_string(self->source));
	fl_value_set_string_take(evt, "duration", fl_value_new_int((int64_t)(duration * 1000)));
	fl_value_set_string_take(evt, "audioTracks", audioTracks);
	fl_value_set_string_take(evt, "subtitleTracks", subtitleTracks);
	fl_event_channel_send(self->eventChannel, evt, NULL, NULL);
	if (!self->streaming) {
		int64_t pos = video_view_plugin_get_pos(self);
		if (pos > 0) {
			video_view_plugin_send_time(self, pos);
		}
		if (self->networking && self->bufferPosition > pos) {
			video_view_plugin_send_buffer(self, pos);
		}
	}
}

static void* video_view_plugin_gl_init(void* addrCtx, const char* name) {
	void* (*func)(const char*) = addrCtx;
	return func(name);
}

static void video_view_plugin_texture_update_callback(void* id) {
	// this function may be called from mpv event thread, so we need to lock the mutex
	g_mutex_lock(&mutex);
	VideoViewPlugin* self = g_tree_lookup(players, id);
	if (self) {
		fl_texture_registrar_mark_texture_frame_available(textureRegistrar, FL_TEXTURE(self));
	}
	g_mutex_unlock(&mutex);
}

static void video_view_plugin_close(VideoViewPlugin* self) {
	video_view_plugin_set_inhibit(self, false);
	self->state = 0;
	self->width = self->height = 0;
	self->position = self->bufferPosition = 0;
	self->overrideAudio = self->overrideSubtitle = 0;
	self->streaming = self->seeking = self->networking = false;
	if (self->source) {
		g_free(self->source);
		self->source = NULL;
	}
	g_array_set_size(self->videoTracks, 0);
	g_array_set_size(self->audioTracks, 0);
	g_array_set_size(self->subtitleTracks, 0);
	const gchar* stop[] = { "stop", NULL };
	mpv_command(self->mpv, stop);
	const gchar* clear[] = { "playlist-clear", NULL };
	mpv_command(self->mpv, clear);
	mpv_set_property_string(self->mpv, "profile", "libmpv");
}

static void video_view_plugin_open(VideoViewPlugin* self, const gchar* source) {
	video_view_plugin_close(self);
	if (!self->mpvRenderContext) {
		GdkDisplay* display = gdk_display_get_default();
		if (display) {
			void* func = NULL;
			if (GDK_IS_WAYLAND_DISPLAY(display)) {
				func = eglGetProcAddress;
			} else if (GDK_IS_X11_DISPLAY(display)) {
				func = glXGetProcAddressARB;
			}
			if (func) {
				mpv_opengl_init_params gl_init_params = { video_view_plugin_gl_init, func };
				mpv_render_param params[] = {
					{ MPV_RENDER_PARAM_API_TYPE, MPV_RENDER_API_TYPE_OPENGL },
					{ MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &gl_init_params },
					{ MPV_RENDER_PARAM_INVALID, NULL }
				};
				if (mpv_render_context_create(&self->mpvRenderContext, self->mpv, params) == MPV_ERROR_SUCCESS) {
					mpv_render_context_set_update_callback(self->mpvRenderContext, video_view_plugin_texture_update_callback, (void*)self->id);
				}
			}
		}
	}
	if (self->mpvRenderContext) {
		int result;
		if (g_str_has_prefix(source, "asset://")) {
			g_autoptr(FlDartProject) project = fl_dart_project_new();
			gchar* path = g_strdup_printf("%s%s", fl_dart_project_get_assets_path(project), &source[7]);
			const gchar* cmd[] = { "loadfile", path, NULL };
			result = mpv_command(self->mpv, cmd);
			g_free(path);
		} else {
			const gchar* cmd[] = { "loadfile", source, NULL };
			result = mpv_command(self->mpv, cmd);
		}
		if (result == MPV_ERROR_SUCCESS) {
			self->state = 1;
			self->source = g_strdup(source);
			video_view_plugin_set_pause(self, TRUE);
		} else {
			g_autoptr(FlValue) evt = fl_value_new_map();
			fl_value_set_string_take(evt, "event", fl_value_new_string("error"));
			fl_value_set_string_take(evt, "event", fl_value_new_string(mpv_error_string(result)));
			fl_event_channel_send(self->eventChannel, evt, NULL, NULL);
		}
	} else {
		g_autoptr(FlValue) evt = fl_value_new_map();
		fl_value_set_string_take(evt, "event", fl_value_new_string("error"));
		fl_value_set_string_take(evt, "value", fl_value_new_string("gl context not available"));
		fl_event_channel_send(self->eventChannel, evt, NULL, NULL);
	}
}

static void video_view_plugin_play(VideoViewPlugin* self) {
	if (self->state == 2) {
		self->state = 3;
		if (video_view_plugin_is_eof(self)) {
			video_view_plugin_just_seek_to(self, 100, true, false);
		}
		video_view_plugin_set_pause(self, FALSE);
		if (self->width > 0 && self->height > 0 && self->keepScreenOn) {
			video_view_plugin_set_inhibit(self, true);
		}
	}
}

static void video_view_plugin_pause(VideoViewPlugin* self) {
	if (self->state > 2) {
		self->state = 2;
		video_view_plugin_set_pause(self, TRUE);
		video_view_plugin_set_inhibit(self, false);
	}
}

static void video_view_plugin_seek_to(VideoViewPlugin* self, const int64_t position, const bool fast) {
	if (self->state == 1) {
		if (self->seeking) {
			video_view_plugin_just_seek_to(self, position, true, false);
		} else {
			self->position = position;
		}
	} else if (self->state > 1) {
		if (video_view_plugin_get_pos(self) != position) {
			video_view_plugin_just_seek_to(self, position, fast, true);
		} else if (!self->seeking) {
			g_autoptr(FlValue) evt = fl_value_new_map();
			fl_value_set_string_take(evt, "event", fl_value_new_string("seekEnd"));
			fl_event_channel_send(self->eventChannel, evt, NULL, NULL);
		}
	}
}

static void video_view_plugin_set_speed(VideoViewPlugin* self, const double speed) {
	self->speed = speed;
	if (!self->streaming) {
		mpv_set_property(self->mpv, "speed", MPV_FORMAT_DOUBLE, &self->speed);
	}
}

static void video_view_plugin_set_volume(VideoViewPlugin* self, const double volume) {
	self->volume = volume * 100;
	mpv_set_property(self->mpv, "volume", MPV_FORMAT_DOUBLE, &self->volume);
}

static void video_view_plugin_set_looping(VideoViewPlugin* self, const bool looping) {
	self->looping = looping;
}

static void video_view_plugin_set_show_subtitle(const VideoViewPlugin* self, const bool show) {
	mpv_set_property_string(self->mpv, "sub-visibility", show ? "yes" : "no");
}

static void video_view_plugin_set_preferred_audio_language(VideoViewPlugin* self, const gchar* language) {
	if (g_strcmp0(self->preferredAudioLanguage, language)) {
		g_free(self->preferredAudioLanguage);
		self->preferredAudioLanguage = g_strdup(language);
		if (self->state > 1 && !self->overrideAudio) {
			video_view_plugin_set_default_track(self, 0);
		}
	}
}

static void video_view_plugin_set_preferred_subtitle_language(VideoViewPlugin* self, const gchar* language) {
	if (g_strcmp0(self->preferredSubtitleLanguage, language)) {
		g_free(self->preferredSubtitleLanguage);
		self->preferredSubtitleLanguage = g_strdup(language);
		if (self->state > 1 && !self->overrideSubtitle) {
			video_view_plugin_set_default_track(self, 1);
		}
	}
}

static void video_view_plugin_set_max_resolution(VideoViewPlugin* self, const uint16_t width, const uint16_t height) {
	self->maxWidth = width;
	self->maxHeight = height;
	if (self->state > 1) {
		video_view_plugin_set_max_size(self);
	}
}

static void video_view_plugin_set_max_bitrate(VideoViewPlugin* self, const uint32_t bitrate) {
	self->maxBitRate = bitrate;
	if (self->state > 1) {
		video_view_plugin_set_max_size(self);
	}
}

static void video_view_plugin_set_keep_screen_on(VideoViewPlugin* self, const bool enable) {
	if (self->keepScreenOn != enable) {
		self->keepScreenOn = enable;
		if (self->state > 2 && self->width > 0 && self->height > 0) {
			video_view_plugin_set_inhibit(self, enable);
		}
	}
}

static void video_view_plugin_overrideTrack(VideoViewPlugin* self, const uint8_t typeId, uint16_t trackId, const bool enabled) {
	if (self->state > 1) {
		gchar* p;
		if (enabled) {
			p = g_strdup_printf("%d", trackId);
		} else {
			p = g_strdup("auto");
			trackId = 0;
		}
		if (typeId) {
			self->overrideSubtitle = trackId;
		} else {
			self->overrideAudio = trackId;
		}
		if (trackId) {
			mpv_set_property_string(self->mpv, typeId ? "sid" : "aid", p);
		} else {
			video_view_plugin_set_default_track(self, typeId);
		}
		g_free(p);
	}
}

static gboolean video_view_plugin_event_callback(void* id) {
	VideoViewPlugin* self = g_tree_lookup(players, id);
	while (self) {
		const mpv_event* event = mpv_wait_event(self->mpv, 0);
		if (event->event_id == MPV_EVENT_NONE) {
			break;
		} else if (self->state > 0) {
			if (event->event_id == MPV_EVENT_PROPERTY_CHANGE) {
				const mpv_event_property* detail = (mpv_event_property*)event->data;
				if (detail->data) {
					if (g_str_equal(detail->name, "time-pos/full")) {
						if (self->state > 0 && !self->streaming) {
							if (self->state > 1) {
								video_view_plugin_send_time(self, (int64_t)(*(double*)detail->data * 1000));
							}
						}
					} else if (g_str_equal(detail->name, "demuxer-cache-time")) {
						if (self->state > 0 && !self->streaming && (self->networking || self->state == 1)) {
							self->bufferPosition = (int64_t)(*(double*)detail->data * 1000);
							if (self->state > 1) {
								video_view_plugin_send_buffer(self, video_view_plugin_get_pos(self));
							}
						}
					} else if (g_str_equal(detail->name, "paused-for-cache")) {
						if (self->state > 2) {
							g_autoptr(FlValue) evt = fl_value_new_map();
							fl_value_set_string_take(evt, "event", fl_value_new_string("loading"));
							fl_value_set_string_take(evt, "value", fl_value_new_bool(*(gboolean*)detail->data));
							fl_event_channel_send(self->eventChannel, evt, NULL, NULL);
						}
					} else if (g_str_equal(detail->name, "pause")) { //listen to pause instead of eof-reached to workaround mpv bug
						if (self->state > 2 && *(gboolean*)detail->data && video_view_plugin_is_eof(self)) {
							if (self->streaming) {
								video_view_plugin_close(self);
							} else if (self->looping) {
								video_view_plugin_just_seek_to(self, 100, true, false);
								video_view_plugin_set_pause(self, FALSE);
							} else {
								self->state = 2;
								video_view_plugin_set_inhibit(self, false);
							}
							g_autoptr(FlValue) evt = fl_value_new_map();
							fl_value_set_string_take(evt, "event", fl_value_new_string("finished"));
							fl_event_channel_send(self->eventChannel, evt, NULL, NULL);
						}
					}
				}
			} else if (event->event_id == MPV_EVENT_END_FILE) {
				mpv_event_end_file* detail = (mpv_event_end_file*)event->data;
				if (detail->reason == MPV_END_FILE_REASON_ERROR) {
					video_view_plugin_close(self);
					g_autoptr(FlValue) evt = fl_value_new_map();
					fl_value_set_string_take(evt, "event", fl_value_new_string("error"));
					fl_value_set_string_take(evt, "value", fl_value_new_string(mpv_error_string(detail->error)));
					fl_event_channel_send(self->eventChannel, evt, NULL, NULL);
				}
			} else if (event->event_id == MPV_EVENT_VIDEO_RECONFIG) {
				if (self->state > 0) {
					const bool hasVideo = self->width > 0 && self->height > 0;
					int64_t tmp;
					mpv_get_property(self->mpv, "dwidth", MPV_FORMAT_INT64, &tmp);
					self->width = (GLsizei)tmp;
					mpv_get_property(self->mpv, "dheight", MPV_FORMAT_INT64, &tmp);
					self->height = (GLsizei)tmp;
					const bool newHasVideo = self->width > 0 && self->height > 0;
					if (self->state > 2 && self->keepScreenOn && hasVideo != newHasVideo) {
						video_view_plugin_set_inhibit(self, newHasVideo);
					}
					g_autoptr(FlValue) evt = fl_value_new_map();
					fl_value_set_string_take(evt, "event", fl_value_new_string("videoSize"));
					fl_value_set_string_take(evt, "width", fl_value_new_float(self->width));
					fl_value_set_string_take(evt, "height", fl_value_new_float(self->height));
					fl_event_channel_send(self->eventChannel, evt, NULL, NULL);
				}
			} else if (event->event_id == MPV_EVENT_PLAYBACK_RESTART) {
				if (self->state == 1) { // file loaded
					self->seeking = false;
					video_view_plugin_loaded(self);
				} else if (self->state > 1 && self->seeking) {
					self->seeking = false;
					g_autoptr(FlValue) evt = fl_value_new_map();
					fl_value_set_string_take(evt, "event", fl_value_new_string("seekEnd"));
					fl_event_channel_send(self->eventChannel, evt, NULL, NULL);
				}
			} else if (event->event_id == MPV_EVENT_FILE_LOADED) {
				// 1) duration unknown or zero is a hint but not decisive
				double duration = 0.0;
				const int dur_rc = mpv_get_property(self->mpv, "duration/full", MPV_FORMAT_DOUBLE, &duration);
				const bool duration_unknown = dur_rc < 0; // unavailable
				const bool duration_zero = (!duration_unknown && duration == 0.0);

				// 2) seekable
				gboolean seekable = FALSE;
				const int sk_rc = mpv_get_property(self->mpv, "seekable", MPV_FORMAT_FLAG, &seekable);
				gboolean partially_seekable = FALSE;
				const int psk_rc = mpv_get_property(self->mpv, "partially-seekable", MPV_FORMAT_FLAG, &partially_seekable);

				// 3) network source
				gboolean networking;
				mpv_get_property(self->mpv, "demuxer-via-network", MPV_FORMAT_FLAG, &networking);
				self->networking = networking == TRUE;

				// 4) demuxer-start-time: often large/non-zero for live (DASH/HLS timebase)
				double demux_start = 0.0;
				const int dst_rc = mpv_get_property(self->mpv, "demuxer-start-time", MPV_FORMAT_DOUBLE, &demux_start);

				// Core rules:
				// - not seekable or only partially seekable over network
				// - duration is unknown and source is network
				// - significant non-zero demux start
				const bool seek_info_known = (sk_rc == 0) || (psk_rc == 0);
				const bool not_fully_seekable = (sk_rc == 0 && !seekable) || (psk_rc == 0 && partially_seekable);

				if (self->networking && (duration_unknown || duration_zero || not_fully_seekable || !seek_info_known || (dst_rc == 0 && demux_start > duration))) {
					self->streaming = true;
				}
				double speed = 1;
				if (self->streaming) {
					mpv_set_property_string(self->mpv, "profile", "low-latency");
				} else {
					speed = self->speed;
					if (self->position > 0) {
						video_view_plugin_just_seek_to(self, self->position, true, true);
						self->position = 0;
					}
				}
				mpv_set_property(self->mpv, "speed", MPV_FORMAT_DOUBLE, &speed);
				mpv_set_property(self->mpv, "volume", MPV_FORMAT_DOUBLE, &self->volume);
			}
		}
	}
	return FALSE;
}

static void video_view_plugin_wakeup_callback(void* id) {
	// make sure event_callback is called in the main thread
	g_idle_add(video_view_plugin_event_callback, id);
}

static gboolean video_view_plugin_texture_populate(FlTextureGL* texture, uint32_t* target, uint32_t* name, uint32_t* width, uint32_t* height, GError** error) {
	VideoViewPlugin* self = VIDEO_VIEW_PLUGIN(texture);
	if (self->state > 0 && self->width > 0 && self->height > 0) {
		if (self->texture == 0 || self->width != self->fbo.w || self->height != self->fbo.h) {
			if (self->texture) {
				glDeleteTextures(1, &self->texture);
			}
			if (self->fbo.fbo) {
				glDeleteFramebuffers(1, (GLuint*)&self->fbo.fbo);
			}
			glGenFramebuffers(1, (GLuint*)&self->fbo.fbo);
			glBindFramebuffer(GL_FRAMEBUFFER, self->fbo.fbo);
			glGenTextures(1, &self->texture);
			glBindTexture(GL_TEXTURE_2D, self->texture);
			glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, self->width, self->height, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
			glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0 + 0, GL_TEXTURE_2D, self->texture, 0);
			if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
				return FALSE;
			}
			self->fbo.w = self->width;
			self->fbo.h = self->height;
		}
		mpv_render_param params[] = {
			{ MPV_RENDER_PARAM_OPENGL_FBO, &self->fbo },
			{ MPV_RENDER_PARAM_INVALID, NULL }
		};
		mpv_render_context_render(self->mpvRenderContext, params);
		*target = GL_TEXTURE_2D;
		*name = self->texture;
		*width = self->width;
		*height = self->height;
		return TRUE;
	}
	return FALSE;
}

static void video_view_plugin_class_init(VideoViewPluginClass* klass) {
	FL_TEXTURE_GL_CLASS(klass)->populate = video_view_plugin_texture_populate;
}

static void video_view_plugin_init(VideoViewPlugin* self) {
	self->texture = 0;
	self->width = self->height = 0;
	self->fbo.fbo = 0;
	self->fbo.w = self->fbo.h = 0;
	self->fbo.internal_format = GL_RGBA8;
	self->speed = 1;
	self->state = 0;
	self->position = self->bufferPosition = 0;
	self->source = NULL;
	self->preferredAudioLanguage = NULL;
	self->preferredSubtitleLanguage = NULL;
	self->looping = self->streaming = self->networking = self->seeking = self->keepScreenOn = false;
	self->mpvRenderContext = NULL;
	self->inhibit_cookie = 0;
}

static VideoViewPlugin* video_view_plugin_new() {
	VideoViewPlugin* self = VIDEO_VIEW_PLUGIN(g_object_new(video_view_plugin_get_type(), NULL));
	FlTexture* texture = FL_TEXTURE(self);
	fl_texture_registrar_register_texture(textureRegistrar, texture);
	self->id = fl_texture_get_id(texture);
	gchar* name = g_strdup_printf("VideoViewPlugin/%ld", self->id);
	self->eventChannel = fl_event_channel_new(messenger, name, codec);
	g_free(name);
	self->mpv = mpv_create();
	self->videoTracks = g_array_new(FALSE, FALSE, sizeof(VideoViewPluginVideoTrack));
	self->audioTracks = g_array_new(FALSE, FALSE, sizeof(VideoViewPluginTrack));
	self->subtitleTracks = g_array_new(FALSE, FALSE, sizeof(VideoViewPluginTrack));
	g_array_set_clear_func(self->audioTracks, video_view_plugin_track_free);
	g_array_set_clear_func(self->subtitleTracks, video_view_plugin_track_free);
	video_view_plugin_set_volume(self, 1.0);
	video_view_plugin_set_show_subtitle(self, false);
	mpv_set_property_string(self->mpv, "vo", "libmpv");
	mpv_set_property_string(self->mpv, "hwdec", "auto-safe");
	mpv_set_property_string(self->mpv, "keep-open", "yes");
	mpv_set_property_string(self->mpv, "idle", "yes");
	mpv_set_property_string(self->mpv, "framedrop", "yes");
	mpv_set_property_string(self->mpv, "stop-screensaver", "no");
	//mpv_set_property_string(self->mpv, "sub-create-cc-track", "yes");
	//mpv_set_property_string(self->mpv, "cache", "no");
	//mpv_set_option_string(self->mpv, "terminal", "yes");
	//mpv_set_option_string(self->mpv, "msg-level", "all=v");
	mpv_initialize(self->mpv);
	mpv_observe_property(self->mpv, 0, "time-pos/full", MPV_FORMAT_DOUBLE);
	mpv_observe_property(self->mpv, 0, "demuxer-cache-time", MPV_FORMAT_DOUBLE);
	mpv_observe_property(self->mpv, 0, "paused-for-cache", MPV_FORMAT_FLAG);
	mpv_observe_property(self->mpv, 0, "pause", MPV_FORMAT_FLAG);
	mpv_set_wakeup_callback(self->mpv, video_view_plugin_wakeup_callback, (void*)self->id);
	return self;
}

static void video_view_plugin_destroy(void* obj) {
	VideoViewPlugin* self = obj;
	video_view_plugin_set_inhibit(self, false);
	fl_texture_registrar_unregister_texture(textureRegistrar, FL_TEXTURE(self));
	g_idle_remove_by_data((void*)self->id);
	//fl_event_channel_send_end_of_stream(self->eventChannel, NULL, NULL);
	g_object_unref(self->eventChannel);
	if (self->mpvRenderContext) {
		mpv_render_context_set_update_callback(self->mpvRenderContext, NULL, NULL);
		mpv_render_context_free(self->mpvRenderContext);
	}
	mpv_set_wakeup_callback(self->mpv, NULL, NULL);
	mpv_destroy(self->mpv);
	g_free(self->source);
	g_free(self->preferredAudioLanguage);
	g_free(self->preferredSubtitleLanguage);
	g_array_free(self->videoTracks, TRUE);
	g_array_free(self->audioTracks, TRUE);
	g_array_free(self->subtitleTracks, TRUE);
	if (self->texture) {
		glDeleteTextures(1, &self->texture);
		self->texture = 0;
	}
	if (self->fbo.fbo) {
		glDeleteFramebuffers(1, (GLuint*)&self->fbo.fbo);
		self->fbo.fbo = 0;
	}
	g_object_unref(self);
}

/* plugin implementation */

static gint video_view_plugin_compare_key(const void* a, const void* b, void* user_data) {
	const int64_t i = (int64_t)a;
	const int64_t j = (int64_t)b;
	if (i > j) {
		return 1;
	} else if (i < j) {
		return -1;
	} else {
		return 0;
	}
}

static gboolean video_view_plugin_remove_player(void* key, void* value, void* tree) {
	g_tree_remove(tree, key);
	return FALSE;
}

static void video_view_plugin_clear() {
	g_mutex_lock(&mutex);
	g_tree_foreach(players, video_view_plugin_remove_player, players);
	g_mutex_unlock(&mutex);
}

static void video_view_plugin_destroy_all(void* data) {
	video_view_plugin_clear();
	g_object_unref(methodChannel);
	g_object_unref(codec);
	g_mutex_clear(&mutex);
	g_tree_destroy(players);
}

static VideoViewPlugin* video_view_plugin_get_player(FlValue* args, const bool isMap) {
	const int64_t id = fl_value_get_int(isMap ? fl_value_lookup_string(args, "id") : args);
	return g_tree_lookup(players, (void*)id);
}

static void video_view_plugin_method_call(FlMethodChannel* channel, FlMethodCall* method_call, void* user_data) {
	const gchar* method = fl_method_call_get_name(method_call);
	FlValue* args = fl_method_call_get_args(method_call);
	g_autoptr(FlMethodResponse) response = NULL;
	if (g_str_equal(method, "create")) {
		VideoViewPlugin* player = video_view_plugin_new();
		g_mutex_lock(&mutex);
		g_tree_insert(players, (void*)player->id, player);
		g_mutex_unlock(&mutex);
		g_autoptr(FlValue) result = fl_value_new_map();
		fl_value_set_string_take(result, "id", fl_value_new_int(player->id));
		response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
	} else if (g_str_equal(method, "dispose")) {
		if (fl_value_get_type(args) == FL_VALUE_TYPE_NULL) {
			video_view_plugin_clear();
		} else {
			const int64_t id = fl_value_get_int(args);
			g_mutex_lock(&mutex);
			g_tree_remove(players, (void*)id);
			g_mutex_unlock(&mutex);
		}
	} else if (g_str_equal(method, "open")) {
		VideoViewPlugin* player = video_view_plugin_get_player(args, true);
		const gchar* value = fl_value_get_string(fl_value_lookup_string(args, "value"));
		video_view_plugin_open(player, value);
	} else if (g_str_equal(method, "close")) {
		VideoViewPlugin* player = video_view_plugin_get_player(args, false);
		video_view_plugin_close(player);
	} else if (g_str_equal(method, "play")) {
		VideoViewPlugin* player = video_view_plugin_get_player(args, false);
		video_view_plugin_play(player);
	} else if (g_str_equal(method, "pause")) {
		VideoViewPlugin* player = video_view_plugin_get_player(args, false);
		video_view_plugin_pause(player);
	} else if (g_str_equal(method, "seekTo")) {
		VideoViewPlugin* player = video_view_plugin_get_player(args, true);
		const int64_t position = fl_value_get_int(fl_value_lookup_string(args, "position"));
		const bool fast = fl_value_get_bool(fl_value_lookup_string(args, "fast"));
		video_view_plugin_seek_to(player, position, fast);
	} else if (g_str_equal(method, "setVolume")) {
		VideoViewPlugin* player = video_view_plugin_get_player(args, true);
		const double value = fl_value_get_float(fl_value_lookup_string(args, "value"));
		video_view_plugin_set_volume(player, value);
	} else if (g_str_equal(method, "setSpeed")) {
		VideoViewPlugin* player = video_view_plugin_get_player(args, true);
		const double value = fl_value_get_float(fl_value_lookup_string(args, "value"));
		video_view_plugin_set_speed(player, value);
	} else if (g_str_equal(method, "setLooping")) {
		VideoViewPlugin* player = video_view_plugin_get_player(args, true);
		const bool value = fl_value_get_bool(fl_value_lookup_string(args, "value"));
		video_view_plugin_set_looping(player, value);
	} else if (g_str_equal(method, "setPreferredAudioLanguage")) {
		VideoViewPlugin* player = video_view_plugin_get_player(args, true);
		const gchar* value = fl_value_get_string(fl_value_lookup_string(args, "value"));
		video_view_plugin_set_preferred_audio_language(player, value[0] == 0 ? NULL : value);
	} else if (g_str_equal(method, "setPreferredSubtitleLanguage")) {
		VideoViewPlugin* player = video_view_plugin_get_player(args, true);
		const gchar* value = fl_value_get_string(fl_value_lookup_string(args, "value"));
		video_view_plugin_set_preferred_subtitle_language(player, value[0] == 0 ? NULL : value);
	} else if (g_str_equal(method, "setMaxBitRate")) {
		VideoViewPlugin* player = video_view_plugin_get_player(args, true);
		const uint32_t value = fl_value_get_int(fl_value_lookup_string(args, "value"));
		video_view_plugin_set_max_bitrate(player, value);
	} else if (g_str_equal(method, "setMaxResolution")) {
		VideoViewPlugin* player = video_view_plugin_get_player(args, true);
		const uint16_t width = (uint16_t)fl_value_get_float(fl_value_lookup_string(args, "width"));
		const uint16_t height = (uint16_t)fl_value_get_float(fl_value_lookup_string(args, "height"));
		video_view_plugin_set_max_resolution(player, width, height);
	} else if (g_str_equal(method, "setShowSubtitle")) {
		const VideoViewPlugin* player = video_view_plugin_get_player(args, true);
		const bool value = fl_value_get_bool(fl_value_lookup_string(args, "value"));
		video_view_plugin_set_show_subtitle(player, value);
	} else if (g_str_equal(method, "setKeepScreenOn")) {
		VideoViewPlugin* player = video_view_plugin_get_player(args, true);
		const bool value = fl_value_get_bool(fl_value_lookup_string(args, "value"));
		video_view_plugin_set_keep_screen_on(player, value);
	} else if (g_str_equal(method, "overrideTrack")) {
		VideoViewPlugin* player = video_view_plugin_get_player(args, true);
		const uint8_t typeId = fl_value_get_int(fl_value_lookup_string(args, "groupId"));
		const uint16_t trackId = fl_value_get_int(fl_value_lookup_string(args, "trackId"));
		const bool enabled = fl_value_get_bool(fl_value_lookup_string(args, "enabled"));
		video_view_plugin_overrideTrack(player, typeId, trackId, enabled);
	} else {
		response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
	}
	if (!response) {
		g_autoptr(FlValue) result = fl_value_new_null();
		response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
	}
	fl_method_call_respond(method_call, response, NULL);
}

/* plugin registration */

void video_view_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
	setlocale(LC_NUMERIC, "C");
	g_mutex_init(&mutex);
	players = g_tree_new_full(video_view_plugin_compare_key, NULL, NULL, video_view_plugin_destroy);
	messenger = fl_plugin_registrar_get_messenger(registrar);
	textureRegistrar = fl_plugin_registrar_get_texture_registrar(registrar);
	codec = FL_METHOD_CODEC(fl_standard_method_codec_new());
	methodChannel = fl_method_channel_new(messenger, "VideoViewPlugin", codec);
	fl_method_channel_set_method_call_handler(methodChannel, video_view_plugin_method_call, NULL, video_view_plugin_destroy_all);
}