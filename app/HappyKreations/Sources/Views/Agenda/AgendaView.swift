import SwiftUI

struct AgendaView: View {
    @EnvironmentObject var store: AppStore
    @State private var moisAffiche: Date = Date()
    @State private var dateSelection: Date = Calendar.current.startOfDay(for: Date())

    var body: some View {
        VStack(spacing: 0) {
            header
            calendrier
            Divider()
            details
        }
        .navigationTitle("Agenda")
    }

    private var header: some View {
        HStack {
            Button { changerMois(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(moisAffiche.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
            Spacer()
            Button { changerMois(1) } label: { Image(systemName: "chevron.right") }
        }
        .padding()
    }

    private var calendrier: some View {
        let cells = joursDuMois
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return VStack(spacing: 6) {
            HStack {
                ForEach(["L", "M", "M", "J", "V", "S", "D"], id: \.self) { d in
                    Text(d).font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(cells, id: \.self) { date in
                    JourCell(date: date,
                             mois: moisAffiche,
                             count: nbCommandes(date),
                             unites: nbUnites(date),
                             plafond: plafond(date),
                             bloque: estBloque(date),
                             selected: Calendar.current.isDate(date, inSameDayAs: dateSelection))
                        .onTapGesture { dateSelection = date }
                }
            }
        }
        .padding(.horizontal)
    }

    private var details: some View {
        let cmds = commandes(date: dateSelection)
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(dateSelection.formatted(date: .complete, time: .omitted))
                        .font(.headline)
                    Spacer()
                    Text("\(cmds.count) commande\(cmds.count > 1 ? "s" : "")")
                        .foregroundStyle(.secondary)
                }
                if cmds.isEmpty {
                    Text("Aucune commande à retirer ce jour.")
                        .foregroundStyle(.secondary).padding(.top)
                } else {
                    ForEach(cmds) { c in
                        NavigationLink(destination: CommandeEditView(commandeId: c.id)) {
                            CommandeRow(commande: c)
                                .padding()
                                .background(RoundedRectangle(cornerRadius: 8).fill(.background.secondary))
                        }
                        .buttonStyle(.plain)
                    }
                }
                chargeSemaine
            }
            .padding()
        }
    }

    private var chargeSemaine: some View {
        PipelineKanbanView()
            .padding(.top, 16)
    }

    // MARK: - Helpers

    private func changerMois(_ delta: Int) {
        if let d = Calendar.current.date(byAdding: .month, value: delta, to: moisAffiche) {
            moisAffiche = d
        }
    }

    private var joursDuMois: [Date] {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2
        let comps = cal.dateComponents([.year, .month], from: moisAffiche)
        let firstDay = cal.date(from: comps)!
        let range = cal.range(of: .day, in: .month, for: firstDay)!
        let weekday = (cal.component(.weekday, from: firstDay) + 5) % 7
        var days: [Date] = []
        for i in 0..<weekday {
            days.append(cal.date(byAdding: .day, value: -(weekday - i), to: firstDay)!)
        }
        for i in 0..<range.count {
            days.append(cal.date(byAdding: .day, value: i, to: firstDay)!)
        }
        while days.count % 7 != 0 {
            days.append(cal.date(byAdding: .day, value: 1, to: days.last!)!)
        }
        return days
    }

    private func commandes(date: Date) -> [Commande] {
        store.commandes.filter {
            guard let d = $0.date_retrait else { return false }
            return Calendar.current.isDate(d, inSameDayAs: date)
                && $0.statut != .annulee
        }
    }

    private func nbCommandes(_ date: Date) -> Int { commandes(date: date).count }
    private func nbUnites(_ date: Date) -> Int {
        commandes(date: date).count
    }
    private func plafond(_ date: Date) -> Int? {
        store.capacites.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) })?.plafond_unites
    }
    private func estBloque(_ date: Date) -> Bool {
        store.capacites.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) })?.bloque ?? false
    }
}

private struct JourCell: View {
    let date: Date
    let mois: Date
    let count: Int
    let unites: Int
    let plafond: Int?
    let bloque: Bool
    let selected: Bool

    var body: some View {
        let inMois = Calendar.current.isDate(date, equalTo: mois, toGranularity: .month)
        VStack(spacing: 2) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.subheadline)
                .foregroundStyle(inMois ? .primary : .secondary)
            if count > 0 {
                Circle().fill(plein ? .red : .blue).frame(width: 6, height: 6)
            } else if bloque {
                Image(systemName: "lock.fill").font(.system(size: 8)).foregroundStyle(.red)
            } else {
                Color.clear.frame(height: 6)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 38)
        .background(background)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(selected ? Color.accentColor : .clear, lineWidth: 2)
        )
    }

    private var plein: Bool {
        if let pl = plafond { return unites >= pl }
        return false
    }
    private var background: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(bloque ? Color.red.opacity(0.08)
                  : (count > 0 ? Color.accentColor.opacity(0.12) : Color.clear))
    }
}
