// Object/System/Class core natives: System.identityHashCode (identity hash,
// null → 0), Class.isInstance (runtime type test), Class.isAssignableFrom
// (compile-time subtype fold). These bottom out the reflective identity/type
// primitives the JDK uses pervasively.
public class CoreNatives {
    interface Animal {}
    static class Dog implements Animal {}
    static class Cat {}
    public static void main(String[] a) {
        Object d = new Dog();
        Object c = new Cat();
        System.out.println(System.identityHashCode(null));                    // 0
        System.out.println(System.identityHashCode(d) != 0 ? 1 : 0);          // 1
        System.out.println(Animal.class.isInstance(d) ? 1 : 0);               // 1
        System.out.println(Animal.class.isInstance(c) ? 1 : 0);               // 0
        System.out.println(Dog.class.isInstance(d) ? 1 : 0);                  // 1
        System.out.println(Animal.class.isAssignableFrom(Dog.class) ? 1 : 0); // 1
        System.out.println(Dog.class.isAssignableFrom(Animal.class) ? 1 : 0); // 0
        System.out.println(Object.class.isAssignableFrom(Cat.class) ? 1 : 0); // 1
    }
}
