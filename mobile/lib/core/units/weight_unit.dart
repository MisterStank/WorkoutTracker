/// The backend always stores/transmits weight in kilograms — WeightUnit is
/// purely a display/input concern on the client, so a unit preference
/// change never needs a migration or touches historical data.
enum WeightUnit {
  kg,
  lb;

  String get label => this == WeightUnit.kg ? 'kg' : 'lb';

  double fromKg(double kg) => this == WeightUnit.kg ? kg : kg * 2.20462262185;

  double toKg(double value) => this == WeightUnit.kg ? value : value / 2.20462262185;

  static WeightUnit fromStorage(String? value) => value == 'lb' ? WeightUnit.lb : WeightUnit.kg;
}
