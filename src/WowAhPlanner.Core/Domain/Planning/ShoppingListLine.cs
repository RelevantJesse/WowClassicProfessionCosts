namespace WowAhPlanner.Core.Domain.Planning;

using WowAhPlanner.Core.Domain;

public sealed record ShoppingListLine(
    int ItemId,
    decimal Quantity,
    Money UnitPrice,
    Money LineCost);

