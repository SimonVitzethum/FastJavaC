// Enum PATTERN-switch → SwitchBootstraps.enumSwitch invokedynamic (distinct from
// the ordinal $SwitchMap tableswitch in EnumSwitch.java). A `case null` forces
// javac to emit the enumSwitch bootstrap. Exercises the frontend's static
// enumSwitch resolution: String labels match an enum constant by reference
// identity (obj == Color.RED), null yields −1, no match yields N (→ default).
public class EnumPatternSwitch {
    enum Color { RED, GREEN, BLUE }

    static int rank(Color c) {
        return switch (c) {
            case RED -> 1;
            case GREEN -> 2;
            case null -> 7;
            default -> 9;      // BLUE has no explicit label → default
        };
    }

    public static void main(String[] args) {
        System.out.println(rank(Color.RED));
        System.out.println(rank(Color.GREEN));
        System.out.println(rank(Color.BLUE));
        System.out.println(rank(null));
    }
}
