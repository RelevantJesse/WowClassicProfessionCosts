namespace WowAhPlanner.Core.Domain;

public readonly record struct Money(long Copper)
{
    public static Money Zero => new(0);

    public static Money FromCopperDecimal(decimal copper)
    {
        var rounded = decimal.Round(copper, 0, MidpointRounding.AwayFromZero);
        return new Money((long)rounded);
    }

    public decimal ToGold() => Copper / 10000m;

    public override string ToString() => $"{ToGold():0.00}g";

    public static Money operator +(Money a, Money b) => new(a.Copper + b.Copper);
    public static Money operator -(Money a, Money b) => new(a.Copper - b.Copper);
    public static Money operator *(Money a, long factor) => new(a.Copper * factor);
    public static Money operator *(Money a, decimal factor) => FromCopperDecimal(a.Copper * factor);
}

