package com.thelogicmaster.cranked;

import java.nio.ByteBuffer;

/**
 * The emulator, through Cranked's JNI binding (java/java.cpp in Cranked, built as libcranked_java.so). The class
 * and method names are fixed by that binding. One instance is one emulator; its methods must be called from one
 * thread, and {@link #updateCallback()} runs on that thread during {@link #update()}.
 */
public class Cranked {
    static {
        System.loadLibrary("cranked_java");
    }

    public static final int STATE_STOPPED = 0, STATE_RUNNING = 1, STATE_STOPPING = 2;

    public static final int DISPLAY_WIDTH = 400, DISPLAY_HEIGHT = 240;

    // PDButtons bits
    public static final int BUTTON_LEFT = 1, BUTTON_RIGHT = 2, BUTTON_UP = 4, BUTTON_DOWN = 8, BUTTON_B = 16,
            BUTTON_A = 32, BUTTON_MENU = 128;

    /** Called once per update, on the emulator thread (the front end feeds audio from here). */
    public interface Listener {
        void onUpdate(Cranked cranked);
    }

    private final long handle;
    private Listener listener;

    /** @param appDataPath the folder that holds every game's data folder */
    public Cranked(String appDataPath) {
        handle = initialize(appDataPath);
    }

    public void setListener(Listener listener) { this.listener = listener; }

    // called from native code during update()
    @SuppressWarnings("unused")
    private void updateCallback() {
        if (listener != null) listener.onUpdate(this);
    }

    /** Loads a game: a .pdx folder or a zipped game. Throws RuntimeException with the message on failure. */
    public void load(String path) { load(handle, path); }
    public void unload() { unload(handle); }
    public void start() { start(handle); }
    /** Runs the emulator for a moment (a frame when one is due). Throws RuntimeException when the game fails. */
    public void update() { update(handle); }
    public void stop() { stop(handle); }
    public void terminate() { terminate(handle); }
    public void reset() { reset(handle); }
    public int getState() { return getState(handle); }
    public void destroy() { destroy(handle); }

    /** Copies the display (400 x 240, RGBA bytes) into a direct buffer of at least 384,000 bytes. */
    public void copyDisplayBuffer(ByteBuffer buffer) { copyDisplayBuffer(handle, buffer); }
    public void setButtons(int buttons) { setButtons(handle, buttons); }
    /** @param angle degrees, 0 pointing up, clockwise; NaN keeps the current angle */
    public void setCrank(float angle, boolean docked) { setCrank(handle, angle, docked); }
    /** Mixes stereo 16-bit audio at 44.1 kHz into a direct buffer of at least frames * 4 bytes. */
    public void sampleAudio(ByteBuffer buffer, int frames) { sampleAudio(handle, buffer, frames); }

    private native long initialize(String appDataPath);
    private static native void destroy(long ptr);
    private static native void load(long ptr, String path);
    private static native void unload(long ptr);
    private static native void start(long ptr);
    private static native void update(long ptr);
    private static native void stop(long ptr);
    private static native void terminate(long ptr);
    private static native void reset(long ptr);
    private static native int getState(long ptr);
    private static native void copyDisplayBuffer(long ptr, ByteBuffer buffer);
    private static native void setButtons(long ptr, int buttons);
    private static native void setCrank(long ptr, float angle, boolean docked);
    private static native void sampleAudio(long ptr, ByteBuffer buffer, int frames);
}
