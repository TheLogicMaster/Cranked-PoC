package org.cranked.poc;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.SharedPreferences;
import android.database.Cursor;
import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioTrack;
import android.net.Uri;
import android.os.Bundle;
import android.provider.OpenableColumns;
import android.view.InputDevice;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;

import com.thelogicmaster.cranked.Cranked;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.concurrent.ConcurrentLinkedQueue;

/**
 * The Cranked Proof of Concept for Android: opens a zipped Playdate game and runs it.
 *
 * A game comes from the system file picker (the Back button opens the app menu, which has Open game), from another
 * app (a zip shared or opened with Cranked), or is the last game played. It is copied into the app's own storage,
 * and the game's save data is kept there too. The emulator runs on its own thread; audio is mixed on that thread
 * after each update and queued to an AudioTrack, as the desktop front end does with SDL.
 */
public class MainActivity extends Activity {
    private static final int REQUEST_OPEN = 1;
    private static final int SAMPLE_RATE = 44100;
    private static final int AUDIO_TARGET_FRAMES = 2048; // queued audio kept at about 46 ms
    private static final int AUDIO_CHUNK_FRAMES = 2048;

    private GameView view;
    private EmulatorThread emulator;
    private SharedPreferences prefs;

    // inputs from keys and gamepads (the view holds the touch ones)
    private volatile int keyButtons, stickButtons;
    private volatile float crankSpeed; // degrees per frame from shoulder buttons or comma/period keys

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        prefs = getSharedPreferences("cranked", MODE_PRIVATE);
        view = new GameView(this);
        view.setControlsVisible(prefs.getBoolean("touchControls", true));
        view.setOnClickListener(v -> { if (emulator != null && !emulator.hasGame()) showMenu(); });
        setContentView(view);
        hideSystemBars();

        emulator = new EmulatorThread(new File(getFilesDir(), "data").getAbsolutePath());
        emulator.start();

        String game = gameFromIntent(getIntent());
        if (game == null) game = prefs.getString("lastGame", null);
        if (game != null && new File(game).exists()) emulator.open(game);
        else view.setMessage("No game loaded.\nPress Back or tap here to open a zipped game (.pdx.zip).");
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        String game = gameFromIntent(intent);
        if (game != null) emulator.open(game);
    }

    @Override
    protected void onResume() {
        super.onResume();
        hideSystemBars();
        emulator.setPaused(false);
    }

    @Override
    protected void onPause() {
        super.onPause();
        emulator.setPaused(true);
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        emulator.quit();
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) hideSystemBars();
    }

    @SuppressWarnings("deprecation")
    private void hideSystemBars() {
        getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_FULLSCREEN | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY | View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN);
    }

    // ---- the app menu (Back) ----

    private void showMenu() {
        String[] items = {
                "Open game",
                "Restart game",
                view.controlsVisible() ? "Hide touch controls" : "Show touch controls",
                "Quit"
        };
        new AlertDialog.Builder(this)
                .setTitle("Cranked")
                .setItems(items, (dialog, which) -> {
                    switch (which) {
                        case 0: pickGame(); break;
                        case 1: emulator.restart(); break;
                        case 2:
                            view.setControlsVisible(!view.controlsVisible());
                            prefs.edit().putBoolean("touchControls", view.controlsVisible()).apply();
                            break;
                        case 3: finish(); break;
                    }
                })
                .show();
    }

    @SuppressWarnings("deprecation")
    private void pickGame() {
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("*/*"); // zip files come with several MIME types, or none
        startActivityForResult(intent, REQUEST_OPEN);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == REQUEST_OPEN && resultCode == RESULT_OK && data != null && data.getData() != null) {
            String game = copyGame(data.getData());
            if (game != null) emulator.open(game);
        }
    }

    private String gameFromIntent(Intent intent) {
        if (intent == null || !Intent.ACTION_VIEW.equals(intent.getAction()) || intent.getData() == null) return null;
        return copyGame(intent.getData());
    }

    /** Copies a picked or shared file into the app's games folder; returns its path, or null (with a message). */
    private String copyGame(Uri uri) {
        String name = "game.pdx.zip";
        try (Cursor cursor = getContentResolver().query(uri, new String[]{OpenableColumns.DISPLAY_NAME}, null, null, null)) {
            if (cursor != null && cursor.moveToFirst() && cursor.getString(0) != null) name = cursor.getString(0);
        } catch (RuntimeException ignored) {
            // a file:// URI or a provider without names: keep the default name
        }
        name = name.replaceAll("[^A-Za-z0-9._ -]", "_");
        File dir = new File(getFilesDir(), "games");
        if (!dir.isDirectory() && !dir.mkdirs()) {
            view.setMessage("Could not create the games folder");
            return null;
        }
        File out = new File(dir, name);
        try (InputStream in = getContentResolver().openInputStream(uri); OutputStream os = new FileOutputStream(out)) {
            if (in == null) throw new java.io.IOException("cannot open " + uri);
            byte[] buffer = new byte[1 << 16];
            for (int n; (n = in.read(buffer)) > 0; ) os.write(buffer, 0, n);
        } catch (Exception e) {
            view.setMessage("Could not read the game:\n" + e.getMessage());
            return null;
        }
        return out.getAbsolutePath();
    }

    // ---- keys and gamepads ----

    private static int buttonForKey(int keyCode) {
        switch (keyCode) {
            case KeyEvent.KEYCODE_DPAD_LEFT: return Cranked.BUTTON_LEFT;
            case KeyEvent.KEYCODE_DPAD_RIGHT: return Cranked.BUTTON_RIGHT;
            case KeyEvent.KEYCODE_DPAD_UP: return Cranked.BUTTON_UP;
            case KeyEvent.KEYCODE_DPAD_DOWN: return Cranked.BUTTON_DOWN;
            // as the desktop front end: a gamepad's bottom button is B and its right button A; Z/A and X/S on keyboards
            case KeyEvent.KEYCODE_BUTTON_A: case KeyEvent.KEYCODE_Z: case KeyEvent.KEYCODE_A: return Cranked.BUTTON_B;
            case KeyEvent.KEYCODE_BUTTON_B: case KeyEvent.KEYCODE_X: case KeyEvent.KEYCODE_S: return Cranked.BUTTON_A;
            case KeyEvent.KEYCODE_BUTTON_START: case KeyEvent.KEYCODE_BUTTON_SELECT: case KeyEvent.KEYCODE_ENTER:
            case KeyEvent.KEYCODE_MENU:
                return Cranked.BUTTON_MENU;
            default: return 0;
        }
    }

    private static float crankForKey(int keyCode) {
        switch (keyCode) {
            case KeyEvent.KEYCODE_BUTTON_L1: case KeyEvent.KEYCODE_COMMA: return -6;
            case KeyEvent.KEYCODE_BUTTON_R1: case KeyEvent.KEYCODE_PERIOD: return 6;
            default: return 0;
        }
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_BACK) return super.onKeyDown(keyCode, event);
        int b = buttonForKey(keyCode);
        float c = crankForKey(keyCode);
        if (b == 0 && c == 0) return super.onKeyDown(keyCode, event);
        keyButtons |= b;
        if (c != 0) crankSpeed = c;
        return true;
    }

    @Override
    public boolean onKeyUp(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_BACK) {
            showMenu();
            return true;
        }
        int b = buttonForKey(keyCode);
        float c = crankForKey(keyCode);
        if (b == 0 && c == 0) return super.onKeyUp(keyCode, event);
        keyButtons &= ~b;
        if (c != 0) crankSpeed = 0;
        return true;
    }

    @Override
    public boolean onGenericMotionEvent(MotionEvent event) {
        if ((event.getSource() & InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK
                && event.getAction() == MotionEvent.ACTION_MOVE) {
            // the left stick and the hat are the d-pad; the right stick points the crank
            float x = event.getAxisValue(MotionEvent.AXIS_X), y = event.getAxisValue(MotionEvent.AXIS_Y);
            float hx = event.getAxisValue(MotionEvent.AXIS_HAT_X), hy = event.getAxisValue(MotionEvent.AXIS_HAT_Y);
            int b = 0;
            if (x < -0.5f || hx < -0.5f) b |= Cranked.BUTTON_LEFT;
            if (x > 0.5f || hx > 0.5f) b |= Cranked.BUTTON_RIGHT;
            if (y < -0.5f || hy < -0.5f) b |= Cranked.BUTTON_UP;
            if (y > 0.5f || hy > 0.5f) b |= Cranked.BUTTON_DOWN;
            stickButtons = b;
            float rx = event.getAxisValue(MotionEvent.AXIS_Z), ry = event.getAxisValue(MotionEvent.AXIS_RZ);
            if (rx * rx + ry * ry > 0.25f) view.setCrankAngle((float) Math.toDegrees(Math.atan2(rx, -ry)));
            return true;
        }
        return super.onGenericMotionEvent(event);
    }

    // ---- the emulator thread ----

    private class EmulatorThread extends Thread implements Cranked.Listener {
        private final String dataPath;
        private final ConcurrentLinkedQueue<Runnable> tasks = new ConcurrentLinkedQueue<>();
        private volatile boolean quit, paused;
        private volatile boolean gameLoaded;
        private boolean failed;
        private Cranked cranked;
        private AudioTrack audio;
        private long audioFramesWritten;
        private final ByteBuffer audioBuffer = ByteBuffer.allocateDirect(AUDIO_CHUNK_FRAMES * 4).order(ByteOrder.nativeOrder());
        private final ByteBuffer display = ByteBuffer.allocateDirect(Cranked.DISPLAY_WIDTH * Cranked.DISPLAY_HEIGHT * 4);
        private String gamePath;

        EmulatorThread(String dataPath) {
            super("Cranked");
            this.dataPath = dataPath;
        }

        boolean hasGame() { return gameLoaded; }

        void open(String path) {
            tasks.add(() -> load(path));
        }

        void restart() {
            tasks.add(() -> { if (gamePath != null) load(gamePath); });
        }

        void setPaused(boolean paused) {
            this.paused = paused;
            tasks.add(() -> {
                if (audio == null) return;
                if (this.paused) { audio.pause(); audio.flush(); }
                else {
                    audio.play();
                    audioFramesWritten = audio.getPlaybackHeadPosition() & 0xFFFFFFFFL; // nothing queued now
                }
            });
        }

        void quit() {
            quit = true;
            interrupt();
        }

        private void load(String path) {
            try {
                cranked.terminate();
                cranked.unload();
                cranked.load(path);
                cranked.start();
                gamePath = path;
                gameLoaded = true;
                failed = false;
                prefs.edit().putString("lastGame", path).apply();
                view.setMessage(null);
            } catch (RuntimeException e) {
                gameLoaded = false;
                view.setMessage("Could not load the game:\n" + e.getMessage());
            }
        }

        @Override
        public void run() {
            new File(dataPath).mkdirs();
            cranked = new Cranked(dataPath);
            cranked.setListener(this);
            int minBuffer = AudioTrack.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_OUT_STEREO, AudioFormat.ENCODING_PCM_16BIT);
            audio = new AudioTrack.Builder()
                    .setAudioAttributes(new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME)
                            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
                    .setAudioFormat(new AudioFormat.Builder().setSampleRate(SAMPLE_RATE)
                            .setEncoding(AudioFormat.ENCODING_PCM_16BIT).setChannelMask(AudioFormat.CHANNEL_OUT_STEREO).build())
                    .setBufferSizeInBytes(Math.max(minBuffer, AUDIO_TARGET_FRAMES * 4 * 2))
                    .setTransferMode(AudioTrack.MODE_STREAM)
                    .build();
            if (!paused) audio.play();

            final long period = 1_000_000_000L / 60; // the loop runs at most 60 times a second (Cranked paces frames)
            long next = System.nanoTime();
            while (!quit) {
                for (Runnable task; (task = tasks.poll()) != null; ) task.run();
                if (paused || !gameLoaded || failed) {
                    try { Thread.sleep(50); } catch (InterruptedException ignored) { }
                    next = System.nanoTime();
                    continue;
                }
                cranked.setButtons(view.touchButtons() | keyButtons | stickButtons);
                if (crankSpeed != 0) view.turnCrank(crankSpeed);
                cranked.setCrank(view.crankAngle(), view.crankDocked());
                try {
                    cranked.update();
                } catch (RuntimeException e) {
                    failed = true;
                    view.setMessage("The game stopped:\n" + e.getMessage());
                }
                if (cranked.getState() == Cranked.STATE_STOPPED && !failed) {
                    failed = true; // the game ended (or never started)
                    view.setMessage("The game has ended.\nPress Back for the menu.");
                }
                cranked.copyDisplayBuffer(display);
                view.showFrame(display);
                next += period;
                long wait = next - System.nanoTime();
                if (wait > 0) {
                    try { Thread.sleep(wait / 1_000_000, (int) (wait % 1_000_000)); } catch (InterruptedException ignored) { }
                } else if (wait < -period) next = System.nanoTime();
            }
            audio.stop();
            audio.release();
            cranked.terminate();
            cranked.destroy();
        }

        // during update, on this thread: keep about AUDIO_TARGET_FRAMES of audio queued
        @Override
        public void onUpdate(Cranked c) {
            if (audio == null || paused) return;
            long played = audio.getPlaybackHeadPosition() & 0xFFFFFFFFL;
            long queued = audioFramesWritten - played;
            int frames = (int) Math.min(AUDIO_CHUNK_FRAMES, AUDIO_TARGET_FRAMES - queued);
            if (frames <= 0) return;
            audioBuffer.clear();
            c.sampleAudio(audioBuffer, frames);
            audioBuffer.position(0);
            audioBuffer.limit(frames * 4);
            int written = audio.write(audioBuffer, frames * 4, AudioTrack.WRITE_NON_BLOCKING);
            if (written > 0) audioFramesWritten += written / 4;
        }
    }
}
