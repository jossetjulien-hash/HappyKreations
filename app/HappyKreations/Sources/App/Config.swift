import Foundation

enum AppConfig {
    /// URL du projet Supabase HappyKreations.
    static let supabaseURL = URL(string: "https://mhbakgmqyegwyuzofzbf.supabase.co")!

    /// Clé publishable Supabase (jamais service_role côté client).
    static let supabaseAnonKey = "sb_publishable_7WXTocSV71ukvradI-sSPg_I90fy09u"

    static let appName = "HappyKreations"
}
