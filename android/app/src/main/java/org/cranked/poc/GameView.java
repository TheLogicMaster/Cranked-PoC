package org.cranked.poc;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Rect;
import android.graphics.RectF;
import android.view.MotionEvent;
import android.view.View;

import com.thelogicmaster.cranked.Cranked;

import java.nio.ByteBuffer;

/**
 * The player view: the Playdate screen, scaled up with whole pixels where it fits, and touch controls around it
 * (a d-pad on the left, B and A on the right, the menu button in the top-left corner, and the crank, a wheel on the
 * right that turns with the finger). Double-tap the wheel to dock or undock the crank.
 */
public class GameView extends View {
    private final Bitmap frame = Bitmap.createBitmap(Cranked.DISPLAY_WIDTH, Cranked.DISPLAY_HEIGHT, Bitmap.Config.ARGB_8888);
    private final Object frameLock = new Object();
    private final Paint pixels = new Paint(); // no filtering: sharp pixels
    private final Paint fill = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint outline = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint label = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Rect screen = new Rect();
    private final Rect source = new Rect(0, 0, Cranked.DISPLAY_WIDTH, Cranked.DISPLAY_HEIGHT);

    // control geometry, in view pixels (set in onSizeChanged)
    private float dpadX, dpadY, dpadR, aX, aY, bX, bY, buttonR, crankX, crankY, crankR, menuX, menuY, menuR;

    private boolean controlsVisible = true;
    private String message;

    // touch state: what each pointer holds
    private static final int MAX_POINTERS = 10;
    private final int[] pointerButtons = new int[MAX_POINTERS];
    private final boolean[] pointerOnCrank = new boolean[MAX_POINTERS];
    private int touchButtons;
    private volatile float crankAngle = 0;
    private volatile boolean crankDocked = true;
    private long lastCrankTap;

    public GameView(Context context) {
        super(context);
        pixels.setFilterBitmap(false);
        outline.setStyle(Paint.Style.STROKE);
        outline.setColor(Color.argb(150, 255, 255, 255));
        label.setColor(Color.argb(170, 255, 255, 255));
        label.setTextAlign(Paint.Align.CENTER);
        frame.eraseColor(Color.rgb(176, 174, 167));
        setFocusable(true);
        setFocusableInTouchMode(true);
    }

    /** Called from the emulator thread with the latest display (RGBA bytes). */
    public void showFrame(ByteBuffer rgba) {
        synchronized (frameLock) {
            rgba.rewind();
            frame.copyPixelsFromBuffer(rgba);
        }
        postInvalidate();
    }

    public void setMessage(String message) {
        this.message = message;
        postInvalidate();
    }

    public void setControlsVisible(boolean visible) {
        controlsVisible = visible;
        requestLayout();
        onSizeChanged(getWidth(), getHeight(), getWidth(), getHeight());
        invalidate();
    }

    public boolean controlsVisible() { return controlsVisible; }

    public int touchButtons() { return controlsVisible ? touchButtons : 0; }
    public float crankAngle() { return crankAngle; }
    public boolean crankDocked() { return crankDocked; }

    /** The crank as turned by a gamepad or keys (degrees, clockwise). */
    public void turnCrank(float degrees) {
        crankAngle = ((crankAngle + degrees) % 360 + 360) % 360;
        crankDocked = false;
    }

    public void setCrankAngle(float degrees) {
        crankAngle = ((degrees % 360) + 360) % 360;
        crankDocked = false;
    }

    @Override
    protected void onSizeChanged(int w, int h, int oldw, int oldh) {
        if (w == 0 || h == 0) return;
        float unit = Math.min(w, h);
        // the screen: as large as fits between the controls, in whole multiples of the display when possible
        int sideSpace = controlsVisible ? (int) (unit * 0.42f) : 0;
        int availW = Math.max(1, w - 2 * sideSpace), availH = h;
        float scale = Math.min(availW / (float) Cranked.DISPLAY_WIDTH, availH / (float) Cranked.DISPLAY_HEIGHT);
        if (scale >= 1) scale = (float) Math.floor(scale);
        int sw = Math.round(Cranked.DISPLAY_WIDTH * scale), sh = Math.round(Cranked.DISPLAY_HEIGHT * scale);
        int sx = (w - sw) / 2, sy = (h - sh) / 2;
        screen.set(sx, sy, sx + sw, sy + sh);

        float side = sideSpace;
        dpadR = side * 0.36f;
        dpadX = side * 0.5f;
        dpadY = h - dpadR - unit * 0.08f;
        buttonR = side * 0.15f;
        bX = w - side * 0.72f;
        bY = h - unit * 0.16f;
        aX = w - side * 0.30f;
        aY = h - unit * 0.24f;
        crankR = side * 0.30f;
        crankX = w - side * 0.5f;
        crankY = crankR + unit * 0.06f;
        menuR = side * 0.12f;
        menuX = side * 0.5f;
        menuY = menuR + unit * 0.06f;
        label.setTextSize(buttonR * 0.8f);
        outline.setStrokeWidth(Math.max(2, unit / 200));
    }

    @Override
    protected void onDraw(Canvas canvas) {
        canvas.drawColor(Color.rgb(24, 24, 24));
        synchronized (frameLock) {
            canvas.drawBitmap(frame, source, screen, pixels);
        }
        if (controlsVisible) drawControls(canvas);
        if (message != null) {
            Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
            p.setColor(Color.argb(210, 0, 0, 0));
            canvas.drawRect(screen, p);
            p.setColor(Color.WHITE);
            p.setTextAlign(Paint.Align.CENTER);
            p.setTextSize(Math.max(24, screen.height() / 12f));
            float y = screen.centerY() - p.getTextSize() * (message.split("\n").length - 1) / 2f;
            for (String line : message.split("\n")) {
                canvas.drawText(line, screen.centerX(), y, p);
                y += p.getTextSize() * 1.3f;
            }
        }
    }

    private void drawControls(Canvas canvas) {
        int held = touchButtons;
        // d-pad: a cross
        float arm = dpadR * 0.36f;
        fill.setColor(Color.argb(70, 255, 255, 255));
        canvas.drawRoundRect(new RectF(dpadX - arm, dpadY - dpadR, dpadX + arm, dpadY + dpadR), arm * 0.4f, arm * 0.4f, fill);
        canvas.drawRoundRect(new RectF(dpadX - dpadR, dpadY - arm, dpadX + dpadR, dpadY + arm), arm * 0.4f, arm * 0.4f, fill);
        fill.setColor(Color.argb(120, 255, 200, 51));
        if ((held & Cranked.BUTTON_UP) != 0) canvas.drawRect(dpadX - arm, dpadY - dpadR, dpadX + arm, dpadY - arm, fill);
        if ((held & Cranked.BUTTON_DOWN) != 0) canvas.drawRect(dpadX - arm, dpadY + arm, dpadX + arm, dpadY + dpadR, fill);
        if ((held & Cranked.BUTTON_LEFT) != 0) canvas.drawRect(dpadX - dpadR, dpadY - arm, dpadX - arm, dpadY + arm, fill);
        if ((held & Cranked.BUTTON_RIGHT) != 0) canvas.drawRect(dpadX + arm, dpadY - arm, dpadX + dpadR, dpadY + arm, fill);
        drawButton(canvas, bX, bY, buttonR, "B", (held & Cranked.BUTTON_B) != 0);
        drawButton(canvas, aX, aY, buttonR, "A", (held & Cranked.BUTTON_A) != 0);
        drawButton(canvas, menuX, menuY, menuR, "≡", (held & Cranked.BUTTON_MENU) != 0);
        // crank: a wheel with a handle at the crank's angle
        canvas.drawCircle(crankX, crankY, crankR, outline);
        double rad = Math.toRadians(crankAngle);
        float hx = crankX + (float) Math.sin(rad) * crankR * 0.75f, hy = crankY - (float) Math.cos(rad) * crankR * 0.75f;
        fill.setColor(crankDocked ? Color.argb(70, 255, 255, 255) : Color.argb(170, 255, 200, 51));
        canvas.drawLine(crankX, crankY, hx, hy, outline);
        canvas.drawCircle(hx, hy, crankR * 0.18f, fill);
        if (crankDocked) canvas.drawText("docked", crankX, crankY + crankR + label.getTextSize(), label);
    }

    private void drawButton(Canvas canvas, float x, float y, float r, String text, boolean held) {
        fill.setColor(held ? Color.argb(150, 255, 200, 51) : Color.argb(70, 255, 255, 255));
        canvas.drawCircle(x, y, r, fill);
        canvas.drawText(text, x, y + label.getTextSize() * 0.35f, label);
    }

    private int buttonsAt(float x, float y) {
        float hit = 1.25f; // generous touch areas
        if (dist(x, y, aX, aY) < buttonR * hit) return Cranked.BUTTON_A;
        if (dist(x, y, bX, bY) < buttonR * hit) return Cranked.BUTTON_B;
        if (dist(x, y, menuX, menuY) < menuR * 1.5f) return Cranked.BUTTON_MENU;
        float dx = x - dpadX, dy = y - dpadY;
        if (dx * dx + dy * dy < dpadR * dpadR * hit * hit) {
            float dead = dpadR * 0.2f;
            int b = 0;
            // eight directions: diagonals press two buttons
            if (Math.abs(dx) > dead && Math.abs(dx) > Math.abs(dy) * 0.4f) b |= dx < 0 ? Cranked.BUTTON_LEFT : Cranked.BUTTON_RIGHT;
            if (Math.abs(dy) > dead && Math.abs(dy) > Math.abs(dx) * 0.4f) b |= dy < 0 ? Cranked.BUTTON_UP : Cranked.BUTTON_DOWN;
            return b;
        }
        return 0;
    }

    private static float dist(float x, float y, float cx, float cy) {
        return (float) Math.hypot(x - cx, y - cy);
    }

    @Override
    public boolean onTouchEvent(MotionEvent event) {
        if (!controlsVisible) {
            if (event.getActionMasked() == MotionEvent.ACTION_UP) performClick();
            return true;
        }
        int action = event.getActionMasked();
        int index = event.getActionIndex();
        switch (action) {
            case MotionEvent.ACTION_DOWN:
            case MotionEvent.ACTION_POINTER_DOWN: {
                int id = event.getPointerId(index);
                if (id >= MAX_POINTERS) break;
                float x = event.getX(index), y = event.getY(index);
                if (dist(x, y, crankX, crankY) < crankR * 1.3f) {
                    long now = event.getEventTime();
                    if (now - lastCrankTap < 300) crankDocked = !crankDocked;
                    lastCrankTap = now;
                    pointerOnCrank[id] = true;
                } else
                    pointerButtons[id] = buttonsAt(x, y);
                break;
            }
            case MotionEvent.ACTION_MOVE:
                for (int i = 0; i < event.getPointerCount(); i++) {
                    int id = event.getPointerId(i);
                    if (id >= MAX_POINTERS) continue;
                    float x = event.getX(i), y = event.getY(i);
                    if (pointerOnCrank[id]) {
                        if (dist(x, y, crankX, crankY) > crankR * 0.15f) {
                            crankAngle = (float) ((Math.toDegrees(Math.atan2(x - crankX, crankY - y)) + 360) % 360);
                            crankDocked = false;
                        }
                    } else
                        pointerButtons[id] = buttonsAt(x, y);
                }
                break;
            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_POINTER_UP:
            case MotionEvent.ACTION_CANCEL: {
                if (action == MotionEvent.ACTION_CANCEL || action == MotionEvent.ACTION_UP) {
                    java.util.Arrays.fill(pointerButtons, 0);
                    java.util.Arrays.fill(pointerOnCrank, false);
                } else {
                    int id = event.getPointerId(index);
                    if (id < MAX_POINTERS) { pointerButtons[id] = 0; pointerOnCrank[id] = false; }
                }
                if (action == MotionEvent.ACTION_UP) performClick();
                break;
            }
        }
        int held = 0;
        for (int b : pointerButtons) held |= b;
        if (held != touchButtons) {
            touchButtons = held;
        }
        invalidate();
        return true;
    }

    @Override
    public boolean performClick() {
        return super.performClick();
    }
}
