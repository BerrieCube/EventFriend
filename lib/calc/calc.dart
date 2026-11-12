/// Basis voor alle calculators: invoervelden, uitkomsten en de
/// stap-voor-stap uitleg die in de uitklapper getoond wordt.
library;

import 'package:flutter/material.dart';

abstract class Field {
  final String id;
  final String label;

  /// Veld alleen tonen als deze functie true geeft (op basis van keuzes).
  final bool Function(Map<String, String> choices)? visibleIf;
  const Field(this.id, this.label, {this.visibleIf});
}

class NumField extends Field {
  final String unit;
  final double def;
  final int decimals;
  const NumField(super.id, super.label,
      {this.unit = '', required this.def, this.decimals = 2, super.visibleIf});
}

class ChoiceField extends Field {
  final List<(String, String)> options; // (waarde, label)
  final String def;
  const ChoiceField(super.id, super.label,
      {required this.options, required this.def, super.visibleIf});
}

class Inputs {
  final Map<String, double> nums;
  final Map<String, String> choices;
  const Inputs(this.nums, this.choices);
  double n(String id) => nums[id]!;
  String c(String id) => choices[id]!;
}

class Res {
  final String label;
  final String value;
  final String unit;
  final bool primary;
  const Res(this.label, this.value, this.unit, this.primary);
}

class Warn {
  final String text;
  final bool severe;
  const Warn(this.text, this.severe);
}

class CalcOutput {
  final results = <Res>[];
  final steps = <String>[];
  final warnings = <Warn>[];
  final extra = <String, double>{};
  String? error;

  void res(String label, String value, {String unit = '', bool primary = false}) =>
      results.add(Res(label, value, unit, primary));
  void step(String s) => steps.add(s);
  void warn(String s, {bool severe = false}) => warnings.add(Warn(s, severe));

  /// Stopt de berekening met een foutmelding voor de gebruiker.
  CalcOutput fail(String msg) {
    error = msg;
    return this;
  }
}

class Calculator {
  final String id;
  final String category;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Field> fields;
  final CalcOutput Function(Inputs) compute;
  final Widget Function(Inputs, CalcOutput)? diagram;
  final String? disclaimer;

  const Calculator({
    required this.id,
    required this.category,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.fields,
    required this.compute,
    this.diagram,
    this.disclaimer,
  });

  /// Rekent uit met de standaardwaarden (handig voor tests).
  CalcOutput computeWith([Map<String, double> nums = const {},
      Map<String, String> choices = const {}]) {
    final n = <String, double>{};
    final c = <String, String>{};
    for (final f in fields) {
      if (f is NumField) n[f.id] = nums[f.id] ?? f.def;
      if (f is ChoiceField) c[f.id] = choices[f.id] ?? f.def;
    }
    return compute(Inputs(n, c));
  }
}
