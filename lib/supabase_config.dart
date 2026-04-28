import 'package:supabase_flutter/supabase_flutter.dart';

const String supabaseUrl = 'https://oxpezfvdrvcbutnzhqtm.supabase.co';
const String supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im94cGV6ZnZkcnZjYnV0bnpocXRtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYzNzY5OTYsImV4cCI6MjA5MTk1Mjk5Nn0.GwD0iZcANkjbRNzFKle0W80jIWyTVIjChobwyieShzI';

/// Global Supabase client instance
SupabaseClient get supabase => Supabase.instance.client;
