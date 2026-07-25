/* Spike: call REAL JDK native leaves (libzip.so's CRC32) through a minimal JNI
 * bridge onto fastjavac's object model — the concrete proof for NATIVE-STRATEGY.md's
 * "cover all natives via libraries" idea.
 *
 * Two calls, increasing bridge depth:
 *   1. Java_java_util_zip_CRC32_update(env, cls, crc, byte) — a PURE native leaf
 *      (no JNIEnv callbacks): shows dlopen + direct invocation works with a dummy env.
 *   2. Java_java_util_zip_CRC32_updateBytes0(env, cls, crc, byte[], off, len) — needs
 *      GetPrimitiveArrayCritical: shows a fastjavac array object ({refcount, vtable,
 *      length, elem_size, data@32}) handed to the JDK leaf through a real JNIEnv slot.
 *
 * Build: cc spikes/jni_bridge.c -I <jdk>/include -I <jdk>/include/linux -ldl -o /tmp/jnispike
 * Run:   /tmp/jnispike <jdk>/lib/libzip.so
 */
#include <jni.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* --- the JVM_* upcalls libzip imports (the HotSpot-internal interface). libzip
 * needs these RESOLVED to load, even though CRC32 never calls them. Providing them
 * ourselves (exported via -rdynamic) is the bridge: fastjavac becomes the "VM" the
 * JDK leaf library links against. Real impls would route to fastjavac's runtime. */
char *JVM_NativePath(char *path) { return path; }               /* canonicalize: identity stub */
void *JVM_RawMonitorCreate(void) { return malloc(1); }          /* opaque token */
void JVM_RawMonitorDestroy(void *m) { free(m); }
int JVM_RawMonitorEnter(void *m) { (void)m; return 0; }         /* single-thread: no real lock */
void JVM_RawMonitorExit(void *m) { (void)m; }

/* fastjavac array layout (see runtime.c): 16-byte header, then length, elem_size, data. */
typedef struct {
    int64_t refcount;
    void *vtable;
    int64_t length;
    int64_t elem_size;
    unsigned char data[]; /* at byte offset 32 */
} FjcArray;

/* --- minimal JNIEnv: only the slots our target leaf actually calls --- */
static void *bridge_GetPrimitiveArrayCritical(JNIEnv *env, jarray arr, jboolean *isCopy) {
    (void)env;
    if (isCopy) *isCopy = JNI_FALSE;          /* we hand back the real storage, no copy */
    return ((char *)arr) + 32;                /* fastjavac array data begins at +32 */
}
static void bridge_ReleasePrimitiveArrayCritical(JNIEnv *env, jarray arr, void *carray, jint mode) {
    (void)env; (void)arr; (void)carray; (void)mode; /* nothing pinned → nothing to do */
}
static jsize bridge_GetArrayLength(JNIEnv *env, jarray arr) {
    (void)env;
    return (jsize)((FjcArray *)arr)->length;
}

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: %s <libzip.so>\n", argv[0]); return 2; }
    void *lib = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!lib) { fprintf(stderr, "dlopen: %s\n", dlerror()); return 3; }

    /* Build a JNIEnv: a table of ~230 fn pointers, mostly NULL, with the 3 we need.
     * JNIEnv (C) == const struct JNINativeInterface_ *, so the leaf receives a
     * JNIEnv* == pointer-to-(pointer-to-table). Pass &table_ptr. */
    struct JNINativeInterface_ tbl;
    memset(&tbl, 0, sizeof tbl);
    tbl.GetPrimitiveArrayCritical = bridge_GetPrimitiveArrayCritical;
    tbl.ReleasePrimitiveArrayCritical = bridge_ReleasePrimitiveArrayCritical;
    tbl.GetArrayLength = bridge_GetArrayLength;
    const struct JNINativeInterface_ *table_ptr = &tbl;
    JNIEnv *env = (JNIEnv *)&table_ptr;

    const char *msg = "hello";

    /* --- 1. pure leaf: CRC32.update(crc, b) byte-by-byte over "hello" (env ignored) --- */
    typedef jint (*update_fn)(JNIEnv *, jclass, jint, jint);
    update_fn crc_update = (update_fn)dlsym(lib, "Java_java_util_zip_CRC32_update");
    if (!crc_update) { fprintf(stderr, "dlsym update: %s\n", dlerror()); return 4; }
    jint crc = 0;
    for (const char *p = msg; *p; p++) crc = crc_update(env, NULL, crc, (jint)(unsigned char)*p);
    printf("update       crc32(\"hello\") = %u\n", (unsigned)(uint32_t)crc);

    /* --- 2. array leaf: CRC32.updateBytes0(crc, byte[], off, len) via the JNIEnv.
     * The leaf calls (*env)->GetPrimitiveArrayCritical; our bridge returns the
     * fastjavac array's data pointer (obj+32). --- */
    typedef jint (*updbytes_fn)(JNIEnv *, jclass, jint, jbyteArray, jint, jint);
    updbytes_fn crc_bytes = (updbytes_fn)dlsym(lib, "Java_java_util_zip_CRC32_updateBytes0");
    if (!crc_bytes) { fprintf(stderr, "dlsym updateBytes0: %s\n", dlerror()); return 5; }
    size_t n = strlen(msg);
    FjcArray *arr = calloc(1, sizeof(FjcArray) + n);
    arr->refcount = 1; arr->vtable = NULL; arr->length = (int64_t)n; arr->elem_size = 1;
    memcpy(arr->data, msg, n);
    jint crc2 = crc_bytes(env, NULL, 0, (jbyteArray)arr, 0, (jint)n);
    printf("updateBytes0 crc32(\"hello\") = %u\n", (unsigned)(uint32_t)crc2);
    free(arr);

    dlclose(lib);
    return 0;
}
