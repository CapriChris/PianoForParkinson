package com.pianoforparkinson.piano_practice;

import java.io.File;
import java.io.IOException;
import java.util.UUID;

/** Moves only an explicitly authorized legacy capture. No scans or overwrites. */
public final class CaptureNamespaceMigration {
    private CaptureNamespaceMigration() {}

    public static synchronized boolean claim(File base, String scope, String capture) throws IOException {
        if (scope == null || !scope.matches("account-[a-f0-9]{64}") || capture == null
                || !capture.matches("[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}")) {
            throw new IllegalArgumentException("Invalid capture ownership");
        }
        String id = UUID.fromString(capture).toString();
        File canonicalBase = base.getCanonicalFile();
        File source = new File(canonicalBase, id);
        File owner = new File(canonicalBase, scope);
        File target = new File(owner, id);
        if (!source.getCanonicalFile().equals(source) || !owner.getCanonicalFile().equals(owner)
                || !target.getCanonicalFile().equals(target)) {
            throw new IOException("Capture paths must remain private");
        }
        if (!source.exists()) return false; // Already moved, or no local ciphertext.
        if (!source.isDirectory() || target.exists()) throw new IOException("Capture destination occupied");
        if (!owner.isDirectory() && !owner.mkdirs()) throw new IOException("Cannot create capture namespace");
        // The capture executor and account OS lease serialize all app writers.
        // File.renameTo works below API 26; never fall back to copy/delete.
        if (target.exists() || !source.renameTo(target)) throw new IOException("Cannot move capture namespace");
        return true;
    }
}
