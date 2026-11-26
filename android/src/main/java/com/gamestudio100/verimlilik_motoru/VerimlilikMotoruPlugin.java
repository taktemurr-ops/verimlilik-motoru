package com.gamestudio100.verimlilik_motoru;

import android.app.AppOpsManager;
import android.app.usage.UsageStats;
import android.app.usage.UsageStatsManager;
import android.content.ActivityNotFoundException;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.net.Uri;
import android.os.Build;
import android.os.Process;
import android.provider.Settings;

import java.util.ArrayList;
import java.util.Calendar;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/** Flutter köprüsü: verimlilik_motoru/focus (odak kilidi, ekran süresi). */
public class VerimlilikMotoruPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
    private MethodChannel focus;
    private Context context;

    @Override
    public void onAttachedToEngine(FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        focus = new MethodChannel(binding.getBinaryMessenger(), "verimlilik_motoru/focus");
        focus.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(FlutterPluginBinding binding) {
        focus.setMethodCallHandler(null);
        focus = null;
    }

    @SuppressWarnings("deprecation")
    private boolean usageGranted() {
        AppOpsManager ops = (AppOpsManager) context.getSystemService(Context.APP_OPS_SERVICE);
        if (ops == null) return false;
        int mode = Build.VERSION.SDK_INT >= 29
                ? ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.getPackageName())
                : ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.getPackageName());
        return mode == AppOpsManager.MODE_ALLOWED;
    }

    private boolean open(Intent i) {
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try {
            context.startActivity(i);
            return true;
        } catch (ActivityNotFoundException | SecurityException e) {
            return false;
        }
    }

    private Set<String> launchable() {
        Intent i = new Intent(Intent.ACTION_MAIN);
        i.addCategory(Intent.CATEGORY_LAUNCHER);
        Set<String> out = new HashSet<>();
        for (ResolveInfo r : context.getPackageManager().queryIntentActivities(i, 0)) {
            out.add(r.activityInfo.packageName);
        }
        out.remove(context.getPackageName());
        return out;
    }

    private String label(String pkg) {
        PackageManager pm = context.getPackageManager();
        try {
            return pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString();
        } catch (PackageManager.NameNotFoundException e) {
            return pkg;
        }
    }

    @Override
    public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        try {
            switch (call.method) {
                case "status": {
                    Map<String, Object> m = new HashMap<>();
                    m.put("usage", usageGranted());
                    m.put("overlay", Settings.canDrawOverlays(context));
                    m.put("running", FocusService.running);
                    m.put("endsAt", FocusService.endsAt);
                    result.success(m);
                    return;
                }
                case "openUsage":
                    result.success(open(new Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)));
                    return;
                case "openOverlay":
                    result.success(open(new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:" + context.getPackageName()))));
                    return;
                case "apps": {
                    List<Map<String, Object>> out = new ArrayList<>();
                    for (String p : launchable()) {
                        Map<String, Object> m = new HashMap<>();
                        m.put("pkg", p);
                        m.put("label", label(p));
                        out.add(m);
                    }
                    Collections.sort(out, (a, b) -> ((String) a.get("label")).compareToIgnoreCase((String) b.get("label")));
                    result.success(out);
                    return;
                }
                case "usage": {
                    if (!usageGranted()) {
                        result.success(new ArrayList<>());
                        return;
                    }
                    UsageStatsManager usm = (UsageStatsManager) context.getSystemService(Context.USAGE_STATS_SERVICE);
                    Calendar c = Calendar.getInstance();
                    c.set(Calendar.HOUR_OF_DAY, 0);
                    c.set(Calendar.MINUTE, 0);
                    c.set(Calendar.SECOND, 0);
                    c.set(Calendar.MILLISECOND, 0);
                    Map<String, UsageStats> agg = usm == null ? null
                            : usm.queryAndAggregateUsageStats(c.getTimeInMillis(), System.currentTimeMillis());
                    List<Map<String, Object>> out = new ArrayList<>();
                    if (agg != null) {
                        Set<String> apps = launchable();
                        for (Map.Entry<String, UsageStats> e : agg.entrySet()) {
                            long ms = e.getValue().getTotalTimeInForeground();
                            if (ms < 60000 || !apps.contains(e.getKey())) continue;
                            Map<String, Object> m = new HashMap<>();
                            m.put("pkg", e.getKey());
                            m.put("label", label(e.getKey()));
                            m.put("ms", ms);
                            out.add(m);
                        }
                    }
                    Collections.sort(out, (a, b) -> Long.compare((Long) b.get("ms"), (Long) a.get("ms")));
                    result.success(out.size() > 25 ? new ArrayList<>(out.subList(0, 25)) : out);
                    return;
                }
                case "start": {
                    List<String> pk = call.argument("packages");
                    Number endsAt = call.argument("endsAt");
                    Intent i = new Intent(context, FocusService.class);
                    i.putExtra("packages", pk == null ? new String[0] : pk.toArray(new String[0]));
                    i.putExtra("endsAt", endsAt == null ? System.currentTimeMillis() + 25 * 60000L : endsAt.longValue());
                    for (String k : new String[] {"title", "body", "blockTitle", "blockBody", "homeLabel", "doneTitle"}) {
                        String v = call.argument(k);
                        i.putExtra(k, v == null ? "" : v);
                    }
                    if (Build.VERSION.SDK_INT >= 26) {
                        context.startForegroundService(i);
                    } else {
                        context.startService(i);
                    }
                    result.success(true);
                    return;
                }
                case "stop":
                    context.stopService(new Intent(context, FocusService.class));
                    result.success(true);
                    return;
                default:
                    result.notImplemented();
            }
        } catch (Exception e) {
            result.error("focus", e.getMessage(), null);
        }
    }
}
