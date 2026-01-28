import SwiftUI

/// History view showing past transcriptions with audio playback
public struct HistoryView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var historyManager = HistoryManager.shared
    @ObservedObject private var playbackManager = AudioPlaybackManager.shared

    @State private var searchText = ""
    @State private var selectedFilter: HistoryFilter = .all
    @State private var showClearConfirmation = false

    public init() {}

    private var filteredItems: [HistoryItem] {
        var items = historyManager.filter(selectedFilter)
        if !searchText.isEmpty {
            items = items.filter {
                $0.text.localizedCaseInsensitiveContains(searchText) ||
                $0.appName?.localizedCaseInsensitiveContains(searchText) == true
            }
        }
        return items
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header with search and filters
            VStack(spacing: 12) {
                HStack {
                    Text("History")
                        .font(.title2)
                        .fontWeight(.bold)

                    Spacer()

                    Button {
                        showClearConfirmation = true
                    } label: {
                        Label("Clear All", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .disabled(historyManager.items.isEmpty)
                }

                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search transcriptions...", text: $searchText)
                        .textFieldStyle(.plain)

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color(.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Filter chips
                HStack(spacing: 8) {
                    ForEach(HistoryFilter.allCases) { filter in
                        filterChip(filter)
                    }

                    Spacer()

                    Text("\(filteredItems.count) items")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(24)

            Divider()

            // Content
            if filteredItems.isEmpty {
                emptyState
            } else {
                historyList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Clear History", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                historyManager.clearAll()
            }
        } message: {
            Text("This will delete all non-starred history items. Starred items will be kept.")
        }
    }

    private var historyList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(filteredItems) { item in
                    HistoryRowView(item: item, onDelete: {
                        historyManager.deleteItem(item)
                    })
                        .contextMenu {
                            Button {
                                copyToClipboard(item.text)
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }

                            Button {
                                historyManager.toggleStar(for: item)
                            } label: {
                                Label(
                                    item.isStarred ? "Unstar" : "Star",
                                    systemImage: item.isStarred ? "star.slash" : "star"
                                )
                            }

                            Divider()

                            Button(role: .destructive) {
                                historyManager.deleteItem(item)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .padding(24)
        }
    }

    private func filterChip(_ filter: HistoryFilter) -> some View {
        Button {
            selectedFilter = filter
        } label: {
            Text(filter.title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selectedFilter == filter ? Color.accentColor : Color(.textBackgroundColor))
                .foregroundColor(selectedFilter == filter ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: emptyStateIcon)
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text(emptyStateTitle)
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(emptyStateMessage)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Spacer()
        }
    }

    private var emptyStateIcon: String {
        if !searchText.isEmpty {
            return "magnifyingglass"
        } else if selectedFilter == .starred {
            return "star"
        } else if selectedFilter == .devApps {
            return "terminal"
        }
        return "clock.arrow.circlepath"
    }

    private var emptyStateTitle: String {
        if !searchText.isEmpty {
            return "No Results"
        } else if selectedFilter == .starred {
            return "No Starred Items"
        } else if selectedFilter == .devApps {
            return "No Dev App Transcriptions"
        }
        return "No History Yet"
    }

    private var emptyStateMessage: String {
        if !searchText.isEmpty {
            return "Try a different search term."
        } else if selectedFilter == .starred {
            return "Star transcriptions to keep them longer."
        } else if selectedFilter == .devApps {
            return "Transcriptions from developer apps will appear here."
        }
        return "Your transcriptions will appear here\nwith audio playback support."
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

/// History filter options
public enum HistoryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case starred = "Starred"
    case devApps = "Dev Apps"

    public var id: String { rawValue }
    public var title: String { rawValue }
}

#Preview {
    HistoryView()
        .environmentObject(AppState.shared)
        .frame(width: 450, height: 500)
}
