//
//  InstanceSetupView.swift
//  fmhy
//
//  First-run (and "change later") picker for the wiki domain.
//

import SwiftUI

struct InstanceSetupView: View {
    let isFirstRun: Bool

    @Environment(WikiStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var selection: String
    @State private var autoFallback: Bool
    @State private var busy = false
    @State private var didProbe = false

    init(isFirstRun: Bool) {
        self.isFirstRun = isFirstRun
        _selection = State(
            initialValue: UserDefaults.standard.string(forKey: WikiStore.primaryInstanceKey)
                ?? WikiInstances.mainID
        )
        _autoFallback = State(
            initialValue: UserDefaults.standard.object(forKey: WikiStore.autoFallbackKey) as? Bool ?? true
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    instanceList
                    fallbackToggle
                    footnote
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { confirmBar }
            .navigationTitle(isFirstRun ? "Welcome" : "Wiki Domain")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if !isFirstRun {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .task {
                guard !didProbe else { return }
                didProbe = true
                await store.probeInstances()
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 500, minHeight: 540, idealHeight: 620)
        #endif
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "globe")
                .font(.system(size: 30))
                .foregroundStyle(.tint)

            Text(isFirstRun ? "Pick your FMHY domain" : "Main wiki domain")
                .font(.title3.weight(.semibold))

            Text(
                "The wiki is already stored on this device and works offline. "
                + "This sets the site the app treats as your home domain and opens sections on."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }

    private var instanceList: some View {
        VStack(spacing: 0) {
            ForEach(Array(WikiInstances.all.enumerated()), id: \.element.id) { index, instance in
                if index > 0 {
                    Divider().padding(.leading, 46)
                }
                row(instance)
            }
        }
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 12))
    }

    private func row(_ instance: WikiInstance) -> some View {
        let isSelected = selection == instance.host
        return Button {
            selection = instance.host
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(instance.host)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(instance.note ?? instance.kind.badge)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
                healthBadge(instance.host)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func healthBadge(_ host: String) -> some View {
        let health = store.instanceHealth[host] ?? .checking
        return HStack(spacing: 5) {
            Circle()
                .fill(color(for: health))
                .frame(width: 6, height: 6)
            Text(label(for: health))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var fallbackToggle: some View {
        Toggle(isOn: $autoFallback) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Fall back to a working mirror")
                    .font(.callout)
                Text("If your domain is down, the next one that responds is used instead.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        #if os(macOS)
        .toggleStyle(.switch)
        #endif
    }

    private var footnote: some View {
        Text(
            "Only original-style FMHY instances are listed — the restyled mirrors "
            + "(FMHY X, Retro FMHY) are skipped. Article text always comes from the official "
            + "GitHub source, so every domain shows the same wiki."
        )
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }

    private var confirmBar: some View {
        Button {
            busy = true
            Task {
                await store.finishSetup(primary: selection, autoFallback: autoFallback)
                busy = false
                dismiss()
            }
        } label: {
            HStack(spacing: 8) {
                if busy {
                    ProgressView().controlSize(.small)
                }
                Text(isFirstRun ? "Start Browsing" : "Save")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(busy)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
    }

    // MARK: - Helpers

    private func color(for health: InstanceHealth) -> Color {
        switch health {
        case .checking: return Color.secondary
        case .online: return Color.green
        case .offline: return Color.orange
        }
    }

    private func label(for health: InstanceHealth) -> String {
        switch health {
        case .checking: return "Checking…"
        case .online: return "Online"
        case .offline: return "Offline"
        }
    }
}

#Preview {
    InstanceSetupView(isFirstRun: true)
        .environment(WikiStore())
}
