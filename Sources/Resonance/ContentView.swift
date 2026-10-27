import SwiftUI
import AppKit

enum Palette {
    static let background = Color(red: 0.047, green: 0.055, blue: 0.078)
    static let panel = Color(red: 0.082, green: 0.094, blue: 0.125)
    static let mint = Color(red: 0.64, green: 0.96, blue: 0.76)
    static let muted = Color(red: 0.53, green: 0.57, blue: 0.64)
    static let line = Color.white.opacity(0.07)
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @AppStorage(AppLanguage.preferenceKey) private var language = AppLanguage.selected

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Palette.line).frame(width: 1)
            VStack(spacing: 0) {
                topbar
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        if model.tab == "download" { downloadPage }
                        else { queuePage }
                    }.padding(34).frame(maxWidth: 1040, alignment: .leading).frame(maxWidth: .infinity)
                }
                footer
            }
        }
        .frame(minWidth: 1000, minHeight: 740)
        .background(Palette.background)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .tint(Palette.mint)
        .environment(\.locale, Locale(identifier: language))
        .sheet(isPresented: $model.showAbout) { about }
        .sheet(isPresented: $model.showLog) { logView }
        .onChange(of: model.options.format) { format in
            if format == .opus, Int(model.options.bitrate) ?? 320 > 256 { model.options.bitrate = "256" }
            model.persist()
        }
        .onChange(of: model.options.bitrate) { _ in model.persist() }
        .onChange(of: model.options.height) { _ in model.persist() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "waveform.path").font(.system(size: 27, weight: .medium)).foregroundStyle(Palette.mint)
                    .frame(width: 42, height: 44).background(Palette.mint.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text("resonance").font(.system(size: 21, weight: .semibold, design: .rounded)).tracking(-0.8)
                    Text("YOUR MEDIA, OFFLINE").font(.system(size: 8, weight: .bold)).tracking(1.5).foregroundStyle(Palette.muted)
                }
            }.padding(.top, 22).padding(.bottom, 46)
            Text("LIBRERIA").font(.system(size: 9, weight: .bold)).tracking(1.7).foregroundStyle(Palette.muted).padding(.leading, 13).padding(.bottom, 13)
            navButton("Nuovo download", symbol: "arrow.down.to.line", tab: "download")
            navButton("Coda e cronologia", symbol: "square.stack.3d.up", tab: "queue", count: model.runningCount)
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "shippingbox").foregroundStyle(Palette.mint)
                    Text("Tutto incluso").font(.system(size: 12, weight: .semibold))
                }
                Text("Audio e video, pronti per il tuo Mac. Nessun componente da installare.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(4)
                HStack(spacing: 5) {
                    Circle().fill(Palette.mint).frame(width: 5, height: 5)
                    Text("Elaborazione sul tuo Mac").font(.system(size: 9)).foregroundStyle(Palette.mint)
                }
            }.padding(16).background(Palette.panel, in: RoundedRectangle(cornerRadius: 15))
            HStack {
                Image(systemName: "globe").foregroundStyle(Palette.muted)
                Picker("Lingua", selection: $language) {
                    Text("Italiano").tag("it")
                    Text("English").tag("en")
                }.labelsHidden().pickerStyle(.menu).accessibilityLabel("Lingua / Language")
            }.padding(.top, 18)
            Button { model.showAbout = true } label: {
                HStack { Image(systemName: "info.circle"); Text("Informazioni"); Spacer(); Text(AppInfo.version).font(.system(size: 10, design: .monospaced)) }
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.top, 24).padding(.bottom, 20)
            }.buttonStyle(.plain)
        }.padding(.horizontal, 18).frame(width: 214).background(Color.black.opacity(0.15))
    }

    private func navButton(_ title: String, symbol: String, tab: String, count: Int = 0) -> some View {
        Button { model.tab = tab } label: {
            HStack(spacing: 11) {
                Image(systemName: symbol).frame(width: 17)
                Text(L(title)).font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
                if count > 0 { Text("\(count)").font(.system(size: 10, weight: .bold)).padding(.horizontal, 6).padding(.vertical, 3).background(Palette.mint.opacity(0.12), in: Capsule()) }
            }.foregroundStyle(model.tab == tab ? Palette.mint : Palette.muted)
                .padding(13).background(model.tab == tab ? Palette.mint.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).padding(.bottom, 4)
    }

    private var topbar: some View {
        HStack {
            Text("IL TUO SPAZIO MULTIMEDIALE").font(.system(size: 9, weight: .semibold)).tracking(1.8).foregroundStyle(Palette.muted)
            Spacer()
            Image(systemName: "desktopcomputer").font(.system(size: 11)).foregroundStyle(Palette.muted)
            Text("Made for Mac").font(.system(size: 10)).foregroundStyle(Palette.muted)
        }.padding(.horizontal, 34).frame(height: 55).overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
    }

    private var downloadPage: some View {
        Group {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Dai link ai tuoi file.").font(.system(size: 32, weight: .semibold)).tracking(-1.3)
                    Text("Scegli la sorgente. Incolla il link. Porta tutto con te.").font(.system(size: 13)).foregroundStyle(Palette.muted)
                }
                Spacer()
                WaveformArt().frame(width: 150, height: 72).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 20) {
                step("01", "Da dove partiamo?")
                HStack(spacing: 12) {
                    ForEach(Service.allCases, id: \.self) { service in
                        Button { model.selectService(service) } label: {
                            HStack(spacing: 13) {
                                Image(systemName: service.symbol).font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(service == .spotify ? Color.green : Color(red: 1, green: 0.35, blue: 0.39))
                                    .frame(width: 45, height: 45).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(service.rawValue).font(.system(size: 16, weight: .semibold))
                                    Text(L(service == .spotify ? "Brani, album e playlist pubbliche" : "Video, Shorts e playlist"))
                                        .font(.system(size: 10)).foregroundStyle(Palette.muted)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: model.service == service ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(model.service == service ? Palette.mint : Palette.muted.opacity(0.5))
                            }.padding(16).background(model.service == service ? Palette.mint.opacity(0.045) : .white.opacity(0.015), in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(model.service == service ? Palette.mint.opacity(0.6) : Palette.line, lineWidth: 1))
                        }.buttonStyle(.plain)
                    }
                }
                HStack(spacing: 12) {
                    Image(systemName: "link").foregroundStyle(Palette.muted)
                    TextField(L(model.service == .spotify ? "Incolla un link Spotify…" : "Incolla un link YouTube…"), text: $model.link)
                        .textFieldStyle(.plain).font(.system(size: 13)).onSubmit { model.analyze() }
                        .accessibilityLabel("Link da analizzare")
                    if !model.link.isEmpty {
                        Button { model.link = ""; model.collection = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted) }.buttonStyle(.plain)
                    }
                    Button { model.paste() } label: { Label("Incolla", systemImage: "doc.on.clipboard").font(.system(size: 11, weight: .medium)) }
                        .buttonStyle(.plain).foregroundStyle(Palette.mint)
                    Rectangle().fill(Palette.line).frame(width: 1, height: 23)
                    if model.inspecting {
                        ProgressView().controlSize(.small)
                        Button("Annulla") { model.cancelInspection() }.buttonStyle(.plain).font(.system(size: 11))
                    } else {
                        Button { model.analyze() } label: { Image(systemName: "arrow.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.background).frame(width: 34, height: 32).background(Palette.mint, in: RoundedRectangle(cornerRadius: 8)) }
                            .buttonStyle(.plain).disabled(model.link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel("Analizza link")
                    }
                }.padding(13).background(Palette.background, in: RoundedRectangle(cornerRadius: 12))
                if model.service == .spotify {
                    Label("Spotify fornisce i titoli. L’audio viene cercato su YouTube: la versione può differire dall’originale.", systemImage: "info.circle")
                        .font(.system(size: 10)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }
                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(Color(red: 1, green: 0.56, blue: 0.52))
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }.card()
            if let collection = model.collection { preview(collection) }
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    step("02", "Come lo vuoi?")
                    Spacer()
                    if model.service == .youtube {
                        HStack(spacing: 3) {
                            ForEach(MediaKind.allCases, id: \.self) { kind in
                                Button { model.setKind(kind) } label: {
                                    Label(L(kind.rawValue), systemImage: kind == .audio ? "music.note" : "video")
                                        .font(.system(size: 11, weight: .medium)).padding(.horizontal, 16).padding(.vertical, 9)
                                        .foregroundStyle(model.options.kind == kind ? .white : Palette.muted)
                                        .background(model.options.kind == kind ? Color.white.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 7))
                                }.buttonStyle(.plain)
                            }
                        }.padding(3).background(Palette.background, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        fieldLabel("FORMATO")
                        HStack(spacing: 6) {
                            ForEach(model.options.kind == .audio ? OutputFormat.audio : OutputFormat.video, id: \.self) { format in
                                Button { model.options.format = format } label: {
                                    Text(format.rawValue).font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                                        .foregroundStyle(model.options.format == format ? Palette.mint : Palette.muted)
                                        .background(model.options.format == format ? Palette.mint.opacity(0.1) : Palette.background, in: RoundedRectangle(cornerRadius: 8))
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(model.options.format == format ? Palette.mint.opacity(0.4) : Palette.line))
                                }.buttonStyle(.plain)
                            }
                        }
                    }.frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 10) {
                        fieldLabel(model.options.kind == .audio ? "QUALITÀ AUDIO" : "RISOLUZIONE MASSIMA")
                        Group {
                            if model.options.kind == .video {
                                Picker("Risoluzione", selection: $model.options.height) {
                                    Text("Migliore disponibile").tag("best")
                                    ForEach(["2160", "1440", "1080", "720", "480", "360"], id: \.self) { Text("\($0)p").tag($0) }
                                }
                            } else if model.options.format.lossless {
                                Text("Senza ulteriore compressione").font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.vertical, 11)
                            } else {
                                Picker("Bitrate", selection: $model.options.bitrate) {
                                    ForEach(model.options.format == .opus ? ["256", "192", "128"] : ["320", "256", "192", "128"], id: \.self) { Text("\($0) kbps").tag($0) }
                                }
                            }
                        }.labelsHidden().pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading).controlSize(.large)
                    }.frame(width: 200)
                }
                Text(L(qualityNote)).font(.system(size: 10)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                Rectangle().fill(Palette.line).frame(height: 1)
                HStack(spacing: 12) {
                    Image(systemName: "folder").foregroundStyle(Palette.mint).font(.system(size: 18))
                    VStack(alignment: .leading, spacing: 5) {
                        fieldLabel("SALVA IN")
                        Text(model.options.destination.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.8)).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Button("Cambia cartella") { model.chooseFolder() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.mint)
                }
            }.card()
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.selectedCount == 0 ? L("Il prossimo passo è un link.") : L(model.selectedCount == 1 ? "%ld elemento pronto" : "%ld elementi pronti", model.selectedCount))
                        .font(.system(size: 13, weight: .medium))
                    Text(model.selectedCount == 0 ? L("Analizzalo per vedere cosa scaricare.") : "\(model.options.format.rawValue) · \(model.options.kind == .audio ? (model.options.format.lossless ? L("Conversione lossless") : model.options.bitrate + " kbps") : (model.options.height == "best" ? L("Qualità migliore") : model.options.height + "p max"))")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Button { model.enqueue() } label: {
                    HStack(spacing: 12) { Image(systemName: "arrow.down.to.line"); Text("Scarica selezionati"); Image(systemName: "arrow.right") }
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.background)
                        .padding(.horizontal, 23).padding(.vertical, 16).background(Palette.mint.opacity(model.selectedCount == 0 ? 0.35 : 1), in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain).disabled(model.selectedCount == 0)
            }
        }
    }

    private var qualityNote: String {
        if model.options.kind == .video {
            return model.options.format == .mp4 ? "MP4 usa H.264 + AAC per una maggiore compatibilità. Per 4K e codec più recenti scegli MKV o WebM. La risoluzione dipende dal video originale." : "Viene scelta la migliore sorgente entro la risoluzione indicata. La qualità effettiva dipende dal video originale."
        }
        return model.options.format.lossless ? "FLAC e WAV preservano il segnale decodificato, ma non recuperano la qualità persa dalla sorgente compressa." : "Il bitrate è quello di esportazione. Un valore più alto non migliora la qualità dell’audio originale."
    }

    private func preview(_ collection: MediaCollection) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(collection.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    Text(L("%ld elementi trovati · %ld selezionati", collection.items.count, model.selectedCount)).font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Button(L(model.selectedCount == collection.items.count ? "Deseleziona tutti" : "Seleziona tutti")) {
                    let selected = model.selectedCount != collection.items.count
                    guard model.collection != nil else { return }
                    for index in model.collection!.items.indices { model.collection!.items[index].selected = selected }
                }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Palette.mint)
            }
            if let notice = collection.notice {
                Label(notice, systemImage: "info.circle").font(.system(size: 10)).foregroundStyle(.orange.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(collection.items) { item in
                        MediaRow(item: Binding(get: { model.collection?.items.first(where: { $0.id == item.id }) ?? item }, set: { value in
                            if let index = model.collection?.items.firstIndex(where: { $0.id == item.id }) { model.collection?.items[index] = value }
                        }))
                        if item.id != collection.items.last?.id { Rectangle().fill(Palette.line).frame(height: 1) }
                    }
                }
            }.frame(height: min(CGFloat(collection.items.count) * 65, 260))
        }.card()
    }

    private var queuePage: some View {
        Group {
            HStack {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Il tuo prossimo ascolto.").font(.system(size: 31, weight: .semibold)).tracking(-1)
                    Text(L("%ld in coda · %ld completati", model.runningCount, model.completedCount)).font(.system(size: 13)).foregroundStyle(Palette.muted)
                }
                Spacer()
                if model.runningCount > 0 { Button("Annulla tutti") { model.cancelAll() }.buttonStyle(.bordered) }
                else if !model.jobs.isEmpty {
                    Button("Pulisci cronologia") { model.jobs.removeAll { $0.state.terminal }; model.persist() }.buttonStyle(.bordered)
                }
            }
            if model.jobs.isEmpty {
                VStack(spacing: 18) {
                    Image(systemName: "arrow.down.circle").font(.system(size: 50, weight: .ultraLight)).foregroundStyle(Palette.mint)
                    Text("Spazio ai tuoi preferiti.").font(.system(size: 20, weight: .medium))
                    Text("I download e i file completati compariranno qui.").font(.system(size: 12)).foregroundStyle(Palette.muted)
                    Button("Aggiungi un link") { model.tab = "download" }.buttonStyle(.borderedProminent).foregroundStyle(Palette.background)
                }.frame(maxWidth: .infinity).padding(.vertical, 100).card()
            } else {
                ForEach(model.jobs.reversed()) { job in
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 13) {
                            Artwork(url: job.item.artwork, symbol: job.options.kind == .audio ? "music.note" : "play.fill").frame(width: 48, height: 48)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(job.item.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                Text("\(job.item.artist) · \(job.options.format.rawValue)").font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
                            }
                            Spacer()
                            Text(L(job.state.rawValue)).font(.system(size: 10, weight: .medium)).foregroundStyle(job.state == .failed ? .orange : Palette.mint)
                                .padding(.horizontal, 10).padding(.vertical, 6).background(.white.opacity(0.04), in: Capsule())
                            if job.state == .completed {
                                Button { model.reveal(job) } label: { Image(systemName: "folder") }.buttonStyle(.plain).help("Mostra nel Finder")
                            } else if job.state == .failed || job.state == .cancelled {
                                Button { model.retry(job.id) } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).help("Riprova")
                            } else {
                                Button { model.cancel(job.id) } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("Annulla")
                            }
                        }
                        if !job.state.terminal { ProgressView(value: job.progress).tint(Palette.mint) }
                        Text(L(job.detail)).font(.system(size: 10)).foregroundStyle(job.state == .failed ? .orange : Palette.muted).textSelection(.enabled)
                        if let matchedTitle = job.item.matchedTitle, let url = job.item.matchedURL, let link = URL(string: url) {
                            Link(L("Sorgente YouTube: %@", matchedTitle), destination: link).font(.system(size: 10)).foregroundStyle(Palette.mint).lineLimit(2)
                        }
                    }.card()
                }
            }
            HStack {
                Image(systemName: "clock").foregroundStyle(Palette.muted)
                Text("La coda viene elaborata in ordine. Lascia aperta l’app fino al completamento.").font(.system(size: 10)).foregroundStyle(Palette.muted)
                Spacer()
                Button("Diagnostica") { model.showLog = true }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Palette.mint)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark.shield").font(.system(size: 10))
            Text("Scarica solo contenuti che possiedi o che sei autorizzato a scaricare.").font(.system(size: 9))
            Spacer()
            Text("RESONANCE / \(AppInfo.version)").font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1.1)
        }.foregroundStyle(Palette.muted.opacity(0.75)).padding(.horizontal, 34).frame(height: 37)
            .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }

    private func step(_ number: String, _ title: String) -> some View {
        HStack(spacing: 11) {
            Text(number).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(Palette.mint)
                .frame(width: 27, height: 27).background(Palette.mint.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
            Text(L(title)).font(.system(size: 14, weight: .semibold))
        }
    }

    private func fieldLabel(_ text: String) -> some View { Text(L(text)).font(.system(size: 8, weight: .bold)).tracking(1.4).foregroundStyle(Palette.muted) }

    private var about: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("resonance").font(.system(size: 28, weight: .semibold, design: .rounded)); Spacer(); Button("Chiudi") { model.showAbout = false } }
            Text("I tuoi media, offline.").foregroundStyle(Palette.mint)
            Text("App nativa per macOS 13 e successivi. Audio: MP3, M4A, FLAC, WAV, Opus. Video: MP4, MKV e WebM.")
            Text("Spotify viene usato per i metadati pubblici; l’audio corrispondente viene cercato su YouTube. Le corrispondenze automatiche possono differire: puoi scegliere un link YouTube per ogni brano. L’anteprima Spotify può contenere solo parte di una raccolta.")
            Text("Il bitrate e il formato indicano la conversione di uscita, non la qualità della sorgente. Contenuti privati, protetti, soggetti a login o limitazioni geografiche possono non essere disponibili.")
            Text("Le connessioni vanno direttamente a Spotify, YouTube e ai loro servizi media. Nessun server Resonance. La cronologia resta in locale.")
            UpdatePreferencesView(updater: model.updates)
            HStack {
                Link("yt-dlp", destination: URL(string: "https://github.com/yt-dlp/yt-dlp")!)
                Link("FFmpeg", destination: URL(string: "https://ffmpeg.org")!)
                Link("QuickJS-ng", destination: URL(string: "https://github.com/quickjs-ng/quickjs")!)
                if let url = AppInfo.repositoryURL { Link("GitHub", destination: url) }
                Spacer()
                Button("Licenze") { if let url = Bundle.main.resourceURL?.appendingPathComponent("Licenses") { NSWorkspace.shared.open(url) } }
            }
        }.font(.system(size: 12)).lineSpacing(4).padding(30).frame(width: 570).background(Palette.background)
    }

    private var logView: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack { Text("Diagnostica della sessione").font(.headline); Spacer(); Button("Chiudi") { model.showLog = false } }
            ScrollView { Text(model.log.isEmpty ? L("Nessuna operazione eseguita.") : model.log).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            Button("Copia") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.log, forType: .string) }
        }.padding(24).frame(width: 740, height: 460).background(Palette.background)
    }
}

struct MediaRow: View {
    @Binding var item: MediaItem
    @State private var showSource = false
    @State private var source = ""
    @State private var error: String?
    var body: some View {
        HStack(spacing: 12) {
            Toggle(L("Seleziona %@", item.title), isOn: $item.selected).labelsHidden().toggleStyle(.checkbox)
            Artwork(url: item.artwork, symbol: item.spotify ? "music.note" : "play.fill").frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(item.artist).font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
            }
            Spacer()
            if item.spotify {
                Button { source = item.matchedURL ?? ""; showSource = true } label: {
                    Image(systemName: item.matchedURL == nil ? "link.badge.plus" : "link").foregroundStyle(Palette.mint)
                }.buttonStyle(.plain).help("Scegli una sorgente YouTube")
                    .popover(isPresented: $showSource) {
                        VStack(alignment: .leading, spacing: 13) {
                            Text("Sorgente YouTube").font(.headline)
                            Text("Imposta il video esatto per questo brano, oppure lascia vuoto per la ricerca automatica.").font(.system(size: 11)).foregroundStyle(Palette.muted)
                            TextField("https://www.youtube.com/watch?v=…", text: $source).textFieldStyle(.roundedBorder)
                            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
                            HStack { Spacer(); Button("Salva") {
                                let clean = source.trimmingCharacters(in: .whitespacesAndNewlines)
                                do {
                                    if !clean.isEmpty { _ = try LinkValidator.normalized(clean, for: .youtube) }
                                    item.matchedURL = clean.isEmpty ? nil : clean; error = nil; showSource = false
                                } catch { self.error = error.localizedDescription }
                            }.buttonStyle(.borderedProminent) }
                        }.padding(20).frame(width: 370)
                    }
            }
            Text(item.durationText).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
        }.padding(.vertical, 11)
    }
}

struct Artwork: View {
    let url: String?
    let symbol: String
    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.mint.opacity(0.18), Color(red: 0.2, green: 0.23, blue: 0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: symbol).foregroundStyle(Palette.mint.opacity(0.7))
            if let url, let link = URL(string: url), link.scheme == "https" {
                AsyncImage(url: link) { image in image.resizable().scaledToFill() } placeholder: { Color.clear }
            }
        }.clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

struct WaveformArt: View {
    private let heights: [CGFloat] = [9, 18, 12, 30, 45, 22, 57, 69, 40, 58, 30, 44, 20, 31, 15, 9]
    var body: some View {
        HStack(spacing: 5) {
            ForEach(heights.indices, id: \.self) { index in
                Capsule().fill(LinearGradient(colors: [Palette.mint.opacity(0.75), Palette.mint.opacity(0.12)], startPoint: .top, endPoint: .bottom)).frame(width: 4, height: heights[index])
            }
        }
    }
}

private extension View {
    func card() -> some View {
        padding(22).background(Palette.panel, in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(Palette.line))
    }
}
