using WowAhPlanner.Core.Domain;

namespace WowAhPlanner.Web.Formatting;

public static class MoneyFormatting
{
    public static string ToGscString(this Money money)
    {
        var sign = money.Copper < 0 ? "-" : "";
        var copper = money.Copper < 0
            ? (ulong)(-(money.Copper + 1)) + 1
            : (ulong)money.Copper;

        if (copper == 0)
        {
            return "0c";
        }

        if (copper >= 10_000)
        {
            var roundedUpToSilver = ((copper + 99) / 100) * 100;
            var gold = roundedUpToSilver / 10_000;
            var silver = (roundedUpToSilver % 10_000) / 100;

            if (silver == 0)
            {
                return $"{sign}{gold}g";
            }

            return $"{sign}{gold}g {silver}s";
        }

        var silverOnly = copper / 100;
        var copperOnly = copper % 100;

        if (silverOnly == 0)
        {
            return $"{sign}{copperOnly}c";
        }

        if (copperOnly == 0)
        {
            return $"{sign}{silverOnly}s";
        }

        return $"{sign}{silverOnly}s {copperOnly}c";
    }
}
