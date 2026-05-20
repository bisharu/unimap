class MapConfig {
  // Replace with your actual values from MapTiler dashboard
  // Floors: ground, 1, 2, 3, 4
  static const String maptilerApiKey = '4O2evtRY0zVi4E3mBrxk';
  
  // Enter your Google Gemini API key from https://aistudio.google.com/
  // static const String geminiApiKey = 'AIzaSyApx-FdeBdzU7Ufa80Jt29YHaCzXpIDjMo';
  
  static String get styleUrl =>
    'https://api.maptiler.com/maps/basic-v2/style.json?key=$maptilerApiKey';
  
  static String get tilesUrl =>
    'https://api.maptiler.com/tiles/v3/{z}/{x}/{y}.pbf?key=$maptilerApiKey';
}
