package com.gamestudio100.verimlilik_motoru;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.app.usage.UsageEvents;
import android.app.usage.UsageStatsManager;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.provider.Settings;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.util.HashSet;
import java.util.Locale;
import java.util.Set;

/**
 * Odak kilidi: odak süresince kullanıcının seçtiği uygulamalardan biri öne
 * gelirse üstte tam ekran bir "odaklan" katmanı gösterir. Ön plandaki
 * uygulama UsageStatsManager olaylarından okunur (Kullanım erişimi izni);
 * katman için "diğer uygulamaların üzerinde göster" izni gerekir. Hiçbir
 * veri cihazdan çıkmaz; ekran içeriği okunmaz.
 */
public class FocusService extends Service {
    static final String ACTION_STOP = "com.gamestudio100.verimlilik_motoru.FOCUS_STOP";
    private static final int NOTE_ID = 7401;
    static volatile boolean running = false;
    static volatile long endsAt = 0;

    private final Handler main = new Handler(Looper.getMainLooper());
    private final Set<String> blocked = new HashSet<>();
    private String title = "", body = "", blockTitle = "", blockBody = "", homeLabel = "", doneTitle = "";
    private long lastQuery = 0;
    private String foreground = null;
    private View overlay;
    private TextView overlayTime;

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    private static String str(String s) {
        return s == null ? "" : s;
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null && ACTION_STOP.equals(intent.getAction())) {
            stopSelf();
            return START_NOT_STICKY;
        }
        if (intent != null) {
            blocked.clear();
            String[] pk = intent.getStringArrayExtra("packages");
            if (pk != null) for (String p : pk) blocked.add(p);
            endsAt = intent.getLongExtra("endsAt", System.currentTimeMillis() + 25 * 60000L);
            title = str(intent.getStringExtra("title"));
            body = str(intent.getStringExtra("body"));
            blockTitle = str(intent.getStringExtra("blockTitle"));
            blockBody = str(intent.getStringExtra("blockBody"));
            homeLabel = str(intent.getStringExtra("homeLabel"));
            doneTitle = str(intent.getStringExtra("doneTitle"));
        }
        channel();
        try {
            if (Build.VERSION.SDK_INT >= 34) {
                startForeground(NOTE_ID, note(false), ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
            } else {
                startForeground(NOTE_ID, note(false));
            }
        } catch (Exception e) {
            stopSelf();
            return START_NOT_STICKY;
        }
        running = true;
        lastQuery = System.currentTimeMillis() - 10000;
        main.removeCallbacks(tick);
        main.post(tick);
        return START_NOT_STICKY;
    }

    private void channel() {
        if (Build.VERSION.SDK_INT < 26) return;
        NotificationManager nm = getSystemService(NotificationManager.class);
        if (nm == null) return;
        NotificationChannel c = new NotificationChannel("focus", title.isEmpty() ? "Focus" : title, NotificationManager.IMPORTANCE_LOW);
        c.setShowBadge(false);
        nm.createNotificationChannel(c);
    }

    @SuppressWarnings("deprecation")
    private Notification note(boolean done) {
        Notification.Builder b = Build.VERSION.SDK_INT >= 26
                ? new Notification.Builder(this, "focus")
                : new Notification.Builder(this);
        b.setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                .setContentTitle(done ? doneTitle : title)
                .setOngoing(!done)
                .setAutoCancel(done);
        if (!done) {
            b.setContentText(body + " " + clock(endsAt));
            if (Build.VERSION.SDK_INT >= 24) {
                b.setUsesChronometer(true).setChronometerCountDown(true).setWhen(endsAt);
            }
        }
        Intent launch = getPackageManager().getLaunchIntentForPackage(getPackageName());
        if (launch != null) {
            b.setContentIntent(PendingIntent.getActivity(this, 4, launch,
                    PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE));
        }
        return b.build();
    }

    private static String clock(long ms) {
        java.util.Calendar c = java.util.Calendar.getInstance();
        c.setTimeInMillis(ms);
        return String.format(Locale.ROOT, "%02d:%02d", c.get(java.util.Calendar.HOUR_OF_DAY), c.get(java.util.Calendar.MINUTE));
    }

    private static String left(long ms) {
        long s = Math.max(0, ms / 1000);
        return String.format(Locale.ROOT, "%d:%02d", s / 60, s % 60);
    }

    private final Runnable tick = new Runnable() {
        @Override
        public void run() {
            long now = System.currentTimeMillis();
            if (now >= endsAt) {
                finish();
                return;
            }
            String fg = currentForeground(now);
            if (fg != null) foreground = fg;
            boolean block = foreground != null && blocked.contains(foreground);
            if (block) showOverlay(endsAt - now);
            else hideOverlay();
            main.postDelayed(this, 700);
        }
    };

    @SuppressWarnings("deprecation")
    private String currentForeground(long now) {
        try {
            UsageStatsManager usm = (UsageStatsManager) getSystemService(Context.USAGE_STATS_SERVICE);
            if (usm == null) return null;
            UsageEvents ev = usm.queryEvents(lastQuery, now);
            lastQuery = now - 500;
            UsageEvents.Event e = new UsageEvents.Event();
            String last = null;
            while (ev.hasNextEvent()) {
                ev.getNextEvent(e);
                if (e.getEventType() == UsageEvents.Event.MOVE_TO_FOREGROUND) last = e.getPackageName();
            }
            return last;
        } catch (Exception e) {
            return null;
        }
    }

    private float dp(float v) {
        return TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, getResources().getDisplayMetrics());
    }

    private void showOverlay(long remaining) {
        if (overlay != null) {
            if (overlayTime != null) overlayTime.setText(left(remaining));
            return;
        }
        if (!Settings.canDrawOverlays(this)) return;
        WindowManager wm = (WindowManager) getSystemService(Context.WINDOW_SERVICE);
        if (wm == null) return;
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setGravity(Gravity.CENTER);
        box.setBackgroundColor(Color.argb(245, 13, 27, 42));
        int pad = (int) dp(32);
        box.setPadding(pad, pad, pad, pad);
        TextView t1 = new TextView(this);
        t1.setText(blockTitle);
        t1.setTextColor(Color.WHITE);
        t1.setTextSize(TypedValue.COMPLEX_UNIT_SP, 26);
        t1.setGravity(Gravity.CENTER);
        TextView t2 = new TextView(this);
        t2.setText(left(remaining));
        t2.setTextColor(Color.rgb(128, 222, 234));
        t2.setTextSize(TypedValue.COMPLEX_UNIT_SP, 54);
        t2.setGravity(Gravity.CENTER);
        TextView t3 = new TextView(this);
        t3.setText(blockBody);
        t3.setTextColor(Color.argb(200, 255, 255, 255));
        t3.setTextSize(TypedValue.COMPLEX_UNIT_SP, 17);
        t3.setGravity(Gravity.CENTER);
        Button home = new Button(this);
        home.setText(homeLabel);
        home.setAllCaps(false);
        home.setOnClickListener(v -> {
            Intent h = new Intent(Intent.ACTION_MAIN);
            h.addCategory(Intent.CATEGORY_HOME);
            h.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            try {
                startActivity(h);
            } catch (Exception ignored) {
            }
            foreground = null;
            hideOverlay();
        });
        box.addView(t1);
        box.addView(t2);
        box.addView(t3);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        lp.topMargin = (int) dp(28);
        box.addView(home, lp);
        int type = Build.VERSION.SDK_INT >= 26
                ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                : WindowManager.LayoutParams.TYPE_PHONE;
        WindowManager.LayoutParams p = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                type,
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT);
        try {
            wm.addView(box, p);
            overlay = box;
            overlayTime = t2;
        } catch (Exception ignored) {
            overlay = null;
            overlayTime = null;
        }
    }

    private void hideOverlay() {
        if (overlay == null) return;
        WindowManager wm = (WindowManager) getSystemService(Context.WINDOW_SERVICE);
        try {
            if (wm != null) wm.removeView(overlay);
        } catch (Exception ignored) {
        }
        overlay = null;
        overlayTime = null;
    }

    private void finish() {
        hideOverlay();
        NotificationManager nm = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm != null && !doneTitle.isEmpty()) {
            try {
                nm.notify(NOTE_ID + 1, note(true));
            } catch (SecurityException ignored) {
            }
        }
        stopSelf();
    }

    @Override
    public void onDestroy() {
        main.removeCallbacks(tick);
        hideOverlay();
        running = false;
        endsAt = 0;
        super.onDestroy();
    }
}
