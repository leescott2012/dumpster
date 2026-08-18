import SwiftUI

/// Collapsible "Advanced" filters row for the Auto-Gen picker phase.
/// Native port of web's `AutoGenAdvanced.tsx` — same sections, same copy,
/// same disabled-when-Surprise behavior. Styling matches AISuggestView's
/// local dark/gold palette (that screen is dark-only and doesn't route
/// through `Theme`'s mode/ColorScheme system).
struct AutoGenAdvancedView: View {
    @Binding var filters: AutoGenFilters
    let availableCategories: [String]
    @Binding var isOpen: Bool

    private var disabled: Bool { filters.mixOn && filters.surprise }

    private var sortedCategories: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in availableCategories {
            let c = raw.trimmingCharacters(in: .whitespaces)
            guard !c.isEmpty, seen.insert(c.lowercased()).inserted else { continue }
            out.append(c)
        }
        return out.sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if isOpen {
                content
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(white: 0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    )
                    .padding(.top, 12)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { isOpen.toggle() }
        } label: {
            HStack {
                HStack(spacing: 8) {
                    Text("ADVANCED")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.5)
                    if !filters.isEmpty {
                        Text("ON")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1)
                            .foregroundColor(Theme.gold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(Theme.gold.opacity(0.15))
                            )
                            .overlay(
                                Capsule().stroke(Theme.gold.opacity(0.35), lineWidth: 1)
                            )
                    }
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
            }
            .foregroundColor(.white.opacity(0.7))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Photos already in a dump are always skipped — Auto Gen only pulls from unused photos.")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.4))
                .lineSpacing(3)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

            mixSection
            whenSection
            timeSection
            if !sortedCategories.isEmpty { categorySection }
            noteSection

            if !filters.isEmpty {
                Button {
                    filters = .empty
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                        Text("Clear all")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    // MARK: - Mix mode

    private var mixSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                filters.mixOn.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Mix it up")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(filters.mixOn ? "ON" : "OFF")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                }
                .foregroundColor(filters.mixOn ? Theme.gold : .white.opacity(0.65))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(filters.mixOn ? Theme.gold.opacity(0.1) : Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(filters.mixOn ? Theme.gold.opacity(0.4) : Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)

            if filters.mixOn {
                VStack(spacing: 4) {
                    FilterCheckboxRow(
                        label: "Surprise me",
                        hint: "Ignore filters — pick from whole pool",
                        checked: $filters.surprise
                    )
                    FilterCheckboxRow(
                        label: "Shuffle on re-gen",
                        hint: "Different result each time you press Auto Gen",
                        checked: $filters.shuffle
                    )
                }
                .padding(.leading, 4)
            }
        }
    }

    // MARK: - When (date range)

    private var whenSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("When")
            HStack(spacing: 8) {
                OptionalDateField(date: $filters.dateFrom, component: .date, disabled: disabled)
                OptionalDateField(date: $filters.dateTo, component: .date, disabled: disabled)
            }
        }
    }

    // MARK: - Time of day

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Time of day")
            HStack(spacing: 8) {
                OptionalDateField(date: $filters.timeFrom, component: .hourAndMinute, disabled: disabled)
                OptionalDateField(date: $filters.timeTo, component: .hourAndMinute, disabled: disabled)
            }
            Text("Photos without EXIF time data are excluded.")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.35))
        }
    }

    // MARK: - Categories

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Categories (any match)")
            FlowLayout(spacing: 6) {
                ForEach(sortedCategories, id: \.self) { cat in
                    let active = filters.categories.contains(cat)
                    Button {
                        if active { filters.categories.remove(cat) } else { filters.categories.insert(cat) }
                    } label: {
                        Text(cat)
                            .font(.system(size: 11, weight: active ? .bold : .semibold))
                            .tracking(0.5)
                            .foregroundColor(active ? .black : .white.opacity(0.6))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(active ? Theme.gold : Color.clear)
                            )
                            .overlay(
                                Capsule().stroke(active ? Color.clear : Color.white.opacity(0.15), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(disabled)
                    .opacity(disabled ? 0.4 : 1)
                }
            }
        }
    }

    // MARK: - Vibe note

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Anything else?")
            TextField(
                "e.g. lean into the warm tones, save my best shot for slide 1",
                text: $filters.vibeNote,
                axis: .vertical
            )
            .font(.system(size: 13))
            .foregroundColor(.white)
            .lineLimit(2...4)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(1.5)
            .foregroundColor(.white.opacity(0.4))
    }
}

// MARK: - Optional date/time field

/// A DatePicker bound to an optional Date — shows a clear (x) button once
/// set. Native platform picker (wheel/compact) stands in for web's
/// `<input type="date">` / `<input type="time">`.
private struct OptionalDateField: View {
    @Binding var date: Date?
    let component: DatePickerComponents
    let disabled: Bool

    var body: some View {
        HStack(spacing: 4) {
            DatePicker(
                "",
                selection: Binding(get: { date ?? Date() }, set: { date = $0 }),
                displayedComponents: component
            )
            .labelsHidden()
            .colorScheme(.dark)
            .tint(Theme.gold)
            .disabled(disabled)

            if date != nil {
                Button {
                    date = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
                .disabled(disabled)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .opacity(disabled ? 0.4 : 1)
    }
}

// MARK: - Checkbox row (Surprise / Shuffle)

private struct FilterCheckboxRow: View {
    let label: String
    let hint: String
    @Binding var checked: Bool

    var body: some View {
        Button {
            checked.toggle()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16))
                    .foregroundColor(checked ? Theme.gold : .white.opacity(0.3))
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(checked ? .white : .white.opacity(0.8))
                    Text(hint)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }
                Spacer()
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
