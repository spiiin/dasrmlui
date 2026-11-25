package org.dasrmlui.demo;

import android.content.pm.PackageManager;
import android.util.Log;

import org.libsdl.app.SDLActivity;

import java.io.IOException;
import java.nio.file.*;
import java.util.ArrayList;
import java.util.List;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

public final class DemoActivity extends SDLActivity {
    // Both daScript LiveHost and RmlUi plugins use ordinary file paths.
    // Publish a complete private runtime once per APK installation.
    private Path runtimeDirectory() throws IOException, PackageManager.NameNotFoundException {
        Path cache = getCacheDir().toPath();
        long version = getPackageManager().getPackageInfo(getPackageName(), 0).lastUpdateTime;
        Path runtime = cache.resolve("runtime-" + version);
        if (Files.isDirectory(runtime)) return runtime;

        Path staging = Files.createTempDirectory(cache, "unpacking-");
        try (ZipInputStream zip = new ZipInputStream(getAssets().open("runtime.zip"))) {
            ZipEntry entry;
            while ((entry = zip.getNextEntry()) != null) {
                Path target = staging.resolve(entry.getName()).normalize();
                if (!target.startsWith(staging)) throw new IOException("Invalid runtime path");
                if (entry.isDirectory()) {
                    Files.createDirectories(target);
                } else {
                    Files.createDirectories(target.getParent());
                    Files.copy(zip, target);
                }
            }
            Files.createDirectories(staging.resolve("logs"));
            return Files.move(staging, runtime, StandardCopyOption.ATOMIC_MOVE);
        } finally {
            if (Files.exists(staging)) removeStagingDirectory(staging);
        }
    }

    private static void removeStagingDirectory(Path directory) throws IOException {
        try (DirectoryStream<Path> children = Files.newDirectoryStream(directory)) {
            for (Path child : children) {
                if (Files.isDirectory(child)) removeStagingDirectory(child);
                else Files.delete(child);
            }
        }
        Files.delete(directory);
    }

    @Override
    protected String[] getArguments() {
        try {
            // Android exposes the same directory under /data/user/0 and
            // /data/data. daScript canonicalizes imports before opening them.
            Path runtime = runtimeDirectory().toRealPath();
            String example = getIntent().getStringExtra("example");
            if (example == null) example = "dashboard";
            if (!example.matches("[a-z][a-z0-9_]*")) throw new IOException("Invalid example name");
            Path script = runtime.resolve("examples").resolve(example + ".das");
            if (!Files.isRegularFile(script)) throw new IOException("Missing example " + example);

            List<String> args = new ArrayList<>();
            args.add(runtime.toString());
            args.add(script.toString());
            if (example.equals("live_lab")) {
                args.add("--watch");
                args.add("--styles");
                args.add(runtime.resolve("examples/live_lab_styles.das").toString());
            }
            if (getIntent().getBooleanExtra("smoke", false)) {
                args.add("--smoke-test");
                if (example.equals("live_lab")) {
                    args.add("--frames");
                    args.add("8");
                }
            }
            return args.toArray(new String[0]);
        } catch (IOException | PackageManager.NameNotFoundException error) {
            Log.e("dasRmlUi", "Could not launch the example", error);
            return new String[0];
        }
    }
}
