import SwiftUI
import Combine
import Foundation
import SwiftSoup

struct ContentView: View {
    
    @State private var clipboardText = ""
    @State private var isEditing = false
    @State private var detectedURL: URL? = nil
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var clipboardHistory: [String] = []
    @State private var showClipboardHistory = false
    @State private var offset = CGSize.zero
    @State private var showArticle = false
    
    private let clipboardUpdatePublisher = NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                VStack {
                    Image(systemName: "doc.on.clipboard")
                        .imageScale(.large)
                        .foregroundColor(.accentColor)
                    
                    ScrollView {
                        VStack {
                            if isEditing {
                                TextEditor(text: $clipboardText)
                                    .frame(minHeight: 200, maxHeight: .infinity)
                                    .padding()
                                    .onChange(of: clipboardText) { newValue in
                                        UIPasteboard.general.string = newValue
                                        saveToClipboardHistory(newValue)
                                    }
                            } else {
                                Text(clipboardText.isEmpty ? "Clipboard is empty" : clipboardText)
                                    .padding()
                                    .onTapGesture {
                                        isEditing.toggle()
                                    }
                            }
                        }
                    }
                    
                    if let url = detectedURL {
                        Button(action: {
                            fetchContents(of: url)
                        }) {
                            if isLoading {
                                ProgressView()
                            } else {
                                Text("Fetch Article Text")
                            }
                        }
                        .padding()
                    }
                    
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .padding()
                    }
                    
                    // Share Button
                    if !clipboardText.isEmpty {
                        ShareLink(item: clipboardText) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .padding()
                    }
                }
                .frame(width: geometry.size.width)
                .offset(x: showClipboardHistory ? -geometry.size.width * 0.4 : 0)
                .onChange(of: showClipboardHistory) { _ in
                    withAnimation(.easeInOut) {
                        offset = showClipboardHistory ? CGSize(width: -geometry.size.width * 0.4, height: 0) : .zero
                    }
                }
                
                if showClipboardHistory {
                    VStack {
                        Text("Clipboard History")
                            .font(.headline)
                            .padding(.top)
                        
                        ScrollView(.vertical) {
                            VStack {
                                ForEach(clipboardHistory, id: \.self) { text in
                                    Text(text)
                                        .padding()
                                        .background(Color.gray.opacity(0.2))
                                        .cornerRadius(8)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .frame(width: geometry.size.width * 0.4)
                    .background(Color.white)
                    .shadow(radius: 10)
                    .offset(x: offset.width)
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                if gesture.translation.width < 0 {
                                    offset = gesture.translation
                                }
                            }
                            .onEnded { _ in
                                if offset.width < -geometry.size.width * 0.2 {
                                    withAnimation(.easeInOut) {
                                        offset.width = -geometry.size.width * 0.4
                                        showClipboardHistory = true
                                    }
                                } else {
                                    withAnimation(.easeInOut) {
                                        offset = .zero
                                        showClipboardHistory = false
                                    }
                                }
                            }
                    )
                }
                
                if showArticle {
                    VStack {
                        Text("Article Content")
                            .font(.headline)
                            .padding()
                        
                        ScrollView {
                            Text(clipboardText)
                                .padding()
                        }
                    }
                    .frame(width: geometry.size.width)
                    .background(Color.white)
                    .transition(.slide)
                    .zIndex(1)
                }
            }
            .gesture(
                TapGesture(count: 2)
                    .onEnded {
                        withAnimation {
                            showArticle.toggle()
                        }
                    }
            )
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        if gesture.translation.width > 0 && showClipboardHistory {
                            offset = gesture.translation
                        }
                    }
                    .onEnded { _ in
                        if offset.width > geometry.size.width * 0.2 {
                            withAnimation(.easeInOut) {
                                offset = .zero
                                showClipboardHistory = false
                            }
                        } else {
                            withAnimation(.easeInOut) {
                                offset.width = -geometry.size.width * 0.4
                            }
                        }
                    }
            )
            .onAppear(perform: updateClipboardText)
            .onReceive(clipboardUpdatePublisher) { _ in
                updateClipboardText()
            }
            .onReceive(NotificationCenter.default.publisher(for: .deviceDidShakeNotification)) { _ in
                revertClipboardToURL()
            }
        }
    }
    
    private func updateClipboardText() {
        if let clipboardString = UIPasteboard.general.string {
            if let url = detectURL(in: clipboardString) {
                detectedURL = url
                clipboardText = clipboardString
            } else {
                detectedURL = nil
                clipboardText = clipboardString
            }
            saveToClipboardHistory(clipboardString)
        } else {
            clipboardText = "Clipboard is empty"
            detectedURL = nil
        }
    }
    
    private func detectURL(in string: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: string, options: [], range: NSRange(location: 0, length: string.utf16.count))
        
        for match in matches ?? [] {
            if let range = Range(match.range, in: string),
               let url = URL(string: String(string[range])) {
                return url
            }
        }
        return nil
    }
    
    private func fetchContents(of url: URL) {
        guard UIApplication.shared.canOpenURL(url) else {
            DispatchQueue.main.async {
                self.errorMessage = "Invalid URL"
                self.isLoading = false
            }
            return
        }
        
        self.isLoading = true
        self.errorMessage = nil
        
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
            }
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to load content: \(error.localizedDescription)"
                }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to load content: No data"
                }
                return
            }
            if let htmlString = String(data: data, encoding: .utf8) {
                do {
                    let bodyText = try self.extractBodyText(from: htmlString)
                    DispatchQueue.main.async {
                        UIPasteboard.general.string = bodyText
                        self.clipboardText = bodyText
                        self.saveToClipboardHistory(bodyText)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.errorMessage = "Failed to load content: \(error.localizedDescription)"
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to load content: Unable to decode data"
                }
            }
        }
        task.resume()
    }
    
    private func extractBodyText(from html: String) throws -> String {
        let document = try SwiftSoup.parse(html)
        let body = try document.body()
        let paragraphs = try body?.select("p").map { try $0.text() }.joined(separator: "\n\n") ?? "Could not extract body text"
        return paragraphs
    }
    
    private func saveToClipboardHistory(_ text: String) {
        if !text.isEmpty && (clipboardHistory.isEmpty || clipboardHistory.last != text) {
            clipboardHistory.append(text)
        }
    }
    
    private func revertClipboardToURL() {
        if let url = detectedURL {
            UIPasteboard.general.string = url.absoluteString
            clipboardText = url.absoluteString
            saveToClipboardHistory(url.absoluteString)
        }
    }
}

extension Notification.Name {
    static let deviceDidShakeNotification = Notification.Name("deviceDidShakeNotification")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShakeNotification, object: nil)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
