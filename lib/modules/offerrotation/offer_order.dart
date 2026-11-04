/// All offers in one list: the administrator's first, then the vendors'. Nothing is left out, however many there are.
List<T> mergeOffers<T>(List<T> adminOffers, List<T> vendorOffers) => [...adminOffers, ...vendorOffers];

/// What the boxes go through. With more offers than boxes, only offers. With fewer, promotions fill the boxes left, so none stands empty.
/// With no offers, the promotions as they are.
List<T> fillBoxes<T>(List<T> offers, List<T> promotions, int boxCount) {
  if (offers.isEmpty) return promotions;
  return [...offers, ...promotions.take(boxCount - offers.length < 0 ? 0 : boxCount - offers.length)];
}
