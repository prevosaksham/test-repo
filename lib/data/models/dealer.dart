import 'package:equatable/equatable.dart';

/// One dealer from `POST /rm/getDealers` (`data[]`).
class Dealer extends Equatable {
  const Dealer({
    required this.id,
    required this.name,
    required this.city,
    required this.state,
  });

  final String id;
  final String name; // dealerName
  final String city;
  final String state;

  /// "Kiren Bajirrao, Nashik" — name plus a title-cased city to tell apart
  /// dealers that share a name.
  String get label {
    final c = city.trim();
    if (c.isEmpty) return name;
    final pretty =
        c[0].toUpperCase() + c.substring(1).toLowerCase();
    return '$name, $pretty';
  }

  factory Dealer.fromJson(Map<String, dynamic> json) {
    // The API isn't consistent about field names across environments, so try a
    // few known aliases and take the first non-empty value. An empty `id` is
    // what crashes the dropdown (duplicate empty values), so this matters most.
    String pick(List<String> keys) {
      for (final k in keys) {
        final v = json[k];
        if (v != null && v.toString().trim().isNotEmpty) return v.toString();
      }
      return '';
    }

    return Dealer(
      id: pick(['id', 'dealerId', 'dealerID', '_id', 'dealershipId']),
      name: pick(['dealerName', 'name', 'dealershipName', 'dealer_name']),
      city: pick(['city', 'cityName', 'dealerCity']),
      state: pick(['state', 'stateName', 'dealerState']),
    );
  }

  @override
  List<Object?> get props => [id, name, city, state];
}
