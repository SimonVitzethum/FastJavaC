/* Spike: LWJGL's native lib (liblwjgl.so) is a self-contained FFI — it needs NO
 * libjvm/JVM_* (unlike the JDK leaf libs). Proves it loads and its generic
 * invoke<shape>(args…, funcAddr) dispatchers call a function pointer. See
 * LWJGL-REQUIREMENTS.md. Build: cc spikes/lwjgl_probe.c -ldl -o /tmp/lp ; run with
 * the path to liblwjgl.so. */
#include <dlfcn.h>
#include <stdio.h>
#include <stdint.h>
static int32_t answer(void) { return 42; }
int main(int c, char **v) {
    if (c < 2) { fprintf(stderr, "usage: %s <liblwjgl.so>\n", v[0]); return 2; }
    void *L = dlopen(v[1], RTLD_NOW | RTLD_LOCAL);   /* no libjvm needed */
    if (!L) { fprintf(stderr, "dlopen: %s\n", dlerror()); return 3; }
    int32_t (*ps)(void *, void *) = (int32_t (*)(void *, void *))
        dlsym(L, "Java_org_lwjgl_system_MemoryAccessJNI_getPointerSize");
    int32_t (*invokeI)(void *, void *, int64_t) = (int32_t (*)(void *, void *, int64_t))
        dlsym(L, "Java_org_lwjgl_system_JNI_invokeI__J");
    printf("getPointerSize = %d\n", ps ? ps(0, 0) : -1);
    printf("invokeI(&fn)   = %d\n", invokeI ? invokeI(0, 0, (int64_t)(intptr_t)answer) : -1);
    return (ps && ps(0, 0) == 8 && invokeI && invokeI(0, 0, (int64_t)(intptr_t)answer) == 42) ? 0 : 1;
}
