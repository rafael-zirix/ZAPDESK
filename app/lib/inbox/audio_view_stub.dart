import 'package:flutter/material.dart';

/// Stub para plataformas não-web (o app roda em Flutter Web por ora).
Widget audioView(String url) => const SizedBox(
      width: 250,
      height: 44,
      child: Center(child: Icon(Icons.audiotrack)),
    );
