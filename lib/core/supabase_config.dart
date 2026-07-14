import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  // URL base do vosso projeto no Supabase
  static const String url = 'https://hnilivakkwvnvgyblmss.supabase.co';
  
  // A vossa chave pública (Anon Key)
  static const String anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJodmlsaXZha2t3dm52Z3libG1zcy5zdXBhYmFzZS5jbyIsImlhdCI6MTcxNjE6IkpX...'; // Coloquem aqui a vossa chave completa que estava no main.dart

  // Método centralizado para inicializar o Supabase no arranque da app
  static Future<void> init() async {
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
    );
  }

  // Atalho estático para aceder ao cliente do Supabase em qualquer ecrã
  // Em vez de: Supabase.instance.client.from(...)
  // Usam apenas: SupabaseConfig.client.from(...)
  static SupabaseClient get client => Supabase.instance.client;
}