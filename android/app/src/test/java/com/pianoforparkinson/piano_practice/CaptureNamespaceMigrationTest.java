package com.pianoforparkinson.piano_practice;

import java.io.File;
import java.nio.file.Files;
import java.util.Arrays;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/** Standalone JVM regression: exercises the exact helper called by CaptureVault. */
public class CaptureNamespaceMigrationTest {
    private static void check(boolean ok) { if (!ok) throw new AssertionError(); }
    private static void rejected(RunnableWithError action) throws Exception {
        try { action.run(); } catch (IllegalArgumentException | java.io.IOException expected) { return; }
        throw new AssertionError("Expected rejection");
    }
    interface RunnableWithError { void run() throws Exception; }
    public static void main(String[] args) throws Exception {
        File base = Files.createTempDirectory("capture-upgrade-").toFile();
        try {
            String scope = "account-" + "a".repeat(64);
            String id = "11111111-1111-4111-8111-111111111111";
            String other = "22222222-2222-4222-8222-222222222222";
            String file = "33333333-3333-4333-8333-333333333333";
            File chunk = new File(base, id + "/" + file + "/0.bin");
            chunk.getParentFile().mkdirs();
            byte[] plain = "original queued recording".getBytes(java.nio.charset.StandardCharsets.UTF_8);
            SecretKey key = KeyGenerator.getInstance("AES").generateKey();
            Cipher encrypt = Cipher.getInstance("AES/GCM/NoPadding");
            encrypt.init(Cipher.ENCRYPT_MODE, key);
            byte[] aad = (id + "/" + file + "/0").getBytes(java.nio.charset.StandardCharsets.UTF_8);
            encrypt.updateAAD(aad);
            byte[] sealed = encrypt.doFinal(plain);
            byte[] bytes = new byte[12 + sealed.length];
            System.arraycopy(encrypt.getIV(), 0, bytes, 0, 12);
            System.arraycopy(sealed, 0, bytes, 12, sealed.length);
            Files.write(chunk.toPath(), bytes);
            File untouched = new File(base, other + "/keep.bin");
            untouched.getParentFile().mkdirs(); Files.write(untouched.toPath(), new byte[]{9,8,7});
            check(CaptureNamespaceMigration.claim(base, scope, id));
            File moved = new File(base, scope + "/" + id + "/" + file + "/0.bin");
            check(!new File(base,id).exists());
            check(Arrays.equals(bytes, Files.readAllBytes(moved.toPath())));
            Cipher decrypt = Cipher.getInstance("AES/GCM/NoPadding");
            decrypt.init(Cipher.DECRYPT_MODE, key, new GCMParameterSpec(128, Arrays.copyOf(bytes,12)));
            decrypt.updateAAD(aad);
            check(Arrays.equals(plain, decrypt.doFinal(Files.readAllBytes(moved.toPath()),12,bytes.length-12)));
            check(!CaptureNamespaceMigration.claim(base,scope,id));
            check(Arrays.equals(new byte[]{9,8,7}, Files.readAllBytes(untouched.toPath())));
            rejected(() -> CaptureNamespaceMigration.claim(base,"../outside",other));
            rejected(() -> CaptureNamespaceMigration.claim(base,scope,"../outside"));
            rejected(() -> CaptureNamespaceMigration.claim(base,null,other));
            File occupied = new File(base,scope + "/" + other); occupied.mkdirs();
            File existing = new File(occupied,"keep.bin"); Files.write(existing.toPath(),new byte[]{1,2,3});
            rejected(() -> CaptureNamespaceMigration.claim(base,scope,other));
            check(Arrays.equals(new byte[]{1,2,3},Files.readAllBytes(existing.toPath())));
            check(Arrays.equals(new byte[]{9,8,7},Files.readAllBytes(untouched.toPath())));
            System.out.println("PASS: ciphertext move/decrypt, idempotence, foreign preservation, invalid paths, no overwrite");
        } finally {
            try (java.util.stream.Stream<java.nio.file.Path> paths = Files.walk(base.toPath())) {
                paths.sorted(java.util.Comparator.reverseOrder()).forEach(path -> { try { Files.delete(path); } catch (Exception e) { throw new RuntimeException(e); } });
            }
        }
    }
}
