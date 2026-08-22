//
//  ElephantChallengeApp.swift
//  Elephant Challenge: Math Memory
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
/// Keep the compact iPhone experience in portrait, while allowing iPad to use
/// the orientation of the device. iPad players commonly use a keyboard case or
/// Stage Manager, so forcing portrait there makes an otherwise adaptive
/// SwiftUI layout feel like an enlarged phone app.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?)
    -> UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .pad ? .all : .portrait
    }
}
#endif

@main
struct ElephantChallengeApp: App {
#if canImport(UIKit)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
#endif
    @AppStorage(GameSettings.onboardingCompleteKey) private var onboardingComplete = false
    @AppStorage(GameSettings.onboardingReplayRequestedKey) private var onboardingReplayRequested = false
    @StateObject private var language = LanguageManager.shared
    @StateObject private var promotedPurchase = PromotedPurchaseCoordinator.shared

    init() {
        // Bring stored progress up to the current version before anything can
        // read it: data written by Jumping Fox must never reach the new game.
        Progress.store.migrateIfNeeded()
        // Decimal answers are printed with the separator of the language the
        // player is reading — a comma in Dutch, a point in English — rather
        // than the device's. The in-app language switch must win here too.
        DecimalAnswer.separatorProvider = {
            LanguageManager.shared.locale.decimalSeparator ?? "."
        }
        // Capture the first launch date independently of when the player first
        // finishes a game; later review phases use age since installation.
        _ = ReviewRequestCoordinator.shared
        PromotedPurchaseCoordinator.shared.startListening()
        // Bring iCloud sync online at launch, not just once the home screen
        // appears — on a fresh reinstall the app opens on onboarding, which
        // never touches ProgressSync, and the saved name would stay missing.
        _ = ProgressSync.shared
        // Install the notification delegate and rebuild the reminder schedule
        // for players who granted permission in an earlier session.
        NotificationManager.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
#if DEBUG
                if PromoMode.isActive {
                    PromoTrailerRoot()
                } else if onboardingComplete && !onboardingReplayRequested {
                    HomeView()
                        // Both screens fade through each other rather than one
                        // replacing the other, so the hand-over reads as a
                        // single settling motion instead of a cut.
                        .transition(.opacity.combined(with: .scale(scale: 1.015)))
                } else {
                    OnboardingView()
                        .transition(.opacity.combined(with: .scale(scale: 0.99)))
                }
#else
                if onboardingComplete && !onboardingReplayRequested {
                    HomeView()
                        // Both screens fade through each other rather than one
                        // replacing the other, so the hand-over reads as a
                        // single settling motion instead of a cut.
                        .transition(.opacity.combined(with: .scale(scale: 1.015)))
                } else {
                    OnboardingView()
                        .transition(.opacity.combined(with: .scale(scale: 0.99)))
                }
#endif
            }
            .animation(.easeInOut(duration: 0.42),
                       value: onboardingComplete && !onboardingReplayRequested)
            // Re-renders every `Text` (and formats numbers) when the language
            // changes; combined with the bundle redirection this makes the
            // switch instant, no restart required.
            .environment(\.locale, language.locale)
            // SwiftUI takes reading direction from the bundle's language, which
            // the in-app switch overrides, so Arabic and Hebrew must be told
            // explicitly to lay out right-to-left.
            .environment(\.layoutDirection, language.layoutDirection)
            // Palettes and copy are authored for light surfaces. Without this,
            // Dark Mode turns system fills black and inverts `.primary` /
            // `.secondary` labels against those same light colours.
            .preferredColorScheme(.light)
            .sheet(isPresented: Binding(
                get: { promotedPurchase.isAwaitingParentApproval },
                set: { isPresented in
                    if !isPresented { promotedPurchase.cancelDeferredPurchase() }
                }
            ),
                   onDismiss: { promotedPurchase.cancelDeferredPurchase() }) {
                let character = CharacterCatalog.current(isPremium: PremiumStore.shared.isPremium)
                ParentApprovalGate(
                    accent: character.color,
                    deepColor: character.deepColor,
                    onApproved: { promotedPurchase.approveDeferredPurchase() }
                )
                .gameEnvironment()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }
}

/// Shared layout helper, used to give iPad more breathing room without
/// changing the visual hierarchy.
enum AppLayout {
#if DEBUG
    /// Trailer captures force phone or pad layout independently of the
    /// simulator they happen to be running on.
    static var promoForcePad: Bool?
#endif

    static var isPad: Bool {
#if DEBUG
        if let promoForcePad { return promoForcePad }
#endif
#if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad
#else
        return false
#endif
    }
}
