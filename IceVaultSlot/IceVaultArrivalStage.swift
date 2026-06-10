import SwiftUI

struct IceVaultArrivalStage: View {
    @EnvironmentObject private var store: IceVaultStore
    @State private var destination: IceVaultLaunchDestination?

    var body: some View {
        Group {
            if let destination {
                switch destination {
                case .web(let url):
                    IceVaultOnlinePassage(url: url) {
                        self.destination = .native
                    }
                case .native, .offline:
                    if store.hasEnteredVault {
                        IceVaultExperience()
                    } else {
                        IceVaultOnboardingView()
                    }
                }
            } else {
                IceVaultLoadingView()
                    .task {
                        destination = await IceVaultSignalGate.resolveDestination()
                    }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: destination)
    }
}

struct IceVaultLoadingView: View {
    @State private var glow = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.01, green: 0.07, blue: 0.22),
                    Color(red: 0.02, green: 0.24, blue: 0.62),
                    Color(red: 0.0, green: 0.54, blue: 0.90)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [Color.cyan.opacity(0.38), Color.clear],
                center: .center,
                startRadius: 30,
                endRadius: 280
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Image("IceVaultLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 260)
                    .shadow(color: Color.cyan.opacity(glow ? 0.60 : 0.26), radius: glow ? 34 : 14)
                    .shadow(color: Color.black.opacity(0.18), radius: 16, x: 0, y: 10)
                    .scaleEffect(glow ? 1.03 : 0.98)
                ProgressView()
                    .tint(.white)
            }
            .padding(28)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                glow.toggle()
            }
        }
    }
}

struct IceVaultOnboardingView: View {
    @EnvironmentObject private var store: IceVaultStore
    @State private var visible = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.01, green: 0.08, blue: 0.25),
                    Color(red: 0.02, green: 0.26, blue: 0.67),
                    Color(red: 0.00, green: 0.55, blue: 0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [Color.cyan.opacity(0.42), Color.clear],
                center: .center,
                startRadius: 40,
                endRadius: 360
            )
            .ignoresSafeArea()

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 22) {
                        Spacer(minLength: 18)
                        Image("IceVaultLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: min(320, proxy.size.width - 56))
                            .padding(.top, 24)
                            .shadow(color: Color.cyan.opacity(0.45), radius: 24, x: 0, y: 12)
                            .opacity(visible ? 1 : 0)
                            .offset(y: visible ? 0 : 18)

                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.14))
                                .frame(width: 290, height: 290)
                                .blur(radius: 28)
                            Image("IceVaultSafe")
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: min(350, proxy.size.width - 34))
                                .shadow(color: Color.black.opacity(0.26), radius: 28, x: 0, y: 18)
                        }
                        .frame(height: min(310, proxy.size.height * 0.36))
                        .opacity(visible ? 1 : 0)
                        .offset(y: visible ? 0 : 24)

                        VStack(spacing: 8) {
                            Text("Ice Vault")
                                .font(.system(size: 42, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 6)
                            Text("Your personal vault for ideas & notes")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Color.white.opacity(0.82))
                                .multilineTextAlignment(.center)
                        }

                        Button {
                            store.hasEnteredVault = true
                        } label: {
                            Label("Enter Vault", systemImage: "snowflake")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(IceVaultTheme.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .shadow(color: Color.black.opacity(0.20), radius: 20, x: 0, y: 12)
                        }
                        .pressScale()
                        .padding(.top, 10)

                        Label("Capture. Organize. Remember.", systemImage: "sparkles")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.16), in: Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1))
                    }
                    .padding(24)
                    .frame(minHeight: proxy.size.height)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.82)) {
                visible = true
            }
        }
    }
}
