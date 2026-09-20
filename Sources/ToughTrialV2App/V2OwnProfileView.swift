import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

struct V2OwnProfileView: View {
    @AppStorage("profile.name") private var name = "Sky"
    @AppStorage("profile.subtitle") private var subtitle = "Tough Trial"
    @AppStorage("profile.phone") private var phone = ""
    @AppStorage("profile.email") private var email = ""
    @AppStorage("profile.douyin") private var douyin = ""
    @AppStorage("profile.xiaohongshu") private var xiaohongshu = ""
    @AppStorage("profile.github") private var github = ""
    @AppStorage("profile.x") private var x = ""

    private var shareText: String {
        [name, subtitle, phone, email]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    identityCard
                    socialSection
                    toolsSection
                }
                .padding(16)
            }
            .background(V2Theme.page)
            .navigationTitle("我的资料")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink("编辑") { V2ProfileEditorView() }
                }
            }
        }
    }

    private var identityCard: some View {
        VStack(spacing: 14) {
            Circle()
                .fill(V2Theme.blue.opacity(0.12))
                .frame(width: 76, height: 76)
                .overlay(Text(initials).font(.title2.weight(.semibold)).foregroundStyle(V2Theme.blue))
            Text(name.isEmpty ? "我的资料" : name).font(.title2.weight(.bold))
            if !subtitle.isEmpty { Text(subtitle).foregroundStyle(.secondary) }
            HStack(spacing: 12) {
                NavigationLink {
                    V2SimpleQRCodeView(title: name.isEmpty ? "我的二维码" : name, payload: shareText)
                } label: {
                    Label("出示二维码", systemImage: "qrcode").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("profile.showQR")

                ShareLink(item: shareText) {
                    Label("分享信息", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("profile.shareInfo")
            }
        }
        .padding(20)
        .background(V2Theme.ColorRole.surfaceRaised, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var socialSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("社交二维码").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                socialCard("抖音", value: douyin, symbol: "play.rectangle")
                socialCard("小红书", value: xiaohongshu, symbol: "book.pages")
                socialCard("GitHub", value: github, symbol: "chevron.left.forwardslash.chevron.right")
                socialCard("X", value: x, symbol: "at")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("其他工具").font(.headline)
            NavigationLink { V2ProfileEditorView() } label: {
                toolRow("编辑我的资料", symbol: "person.text.rectangle")
            }
            NavigationLink {
                ContentUnavailableView("名片扫描与整理", systemImage: "viewfinder", description: Text("低频的名片扫描、识别和联系人整理入口。"))
            } label: {
                toolRow("名片扫描与联系人", symbol: "viewfinder")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var initials: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "我" : String(trimmed.prefix(2)).uppercased()
    }

    private func socialCard(_ title: String, value: String, symbol: String) -> some View {
        NavigationLink {
            if value.isEmpty { V2ProfileEditorView() }
            else { V2SimpleQRCodeView(title: title, payload: value) }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: symbol).foregroundStyle(V2Theme.blue)
                    Spacer()
                    Image(systemName: value.isEmpty ? "plus.circle" : "qrcode").foregroundStyle(.secondary)
                }
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(value.isEmpty ? "添加账号或主页链接" : "点按出示二维码")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .padding(14)
            .background(V2Theme.ColorRole.surfaceRaised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func toolRow(_ title: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 28).foregroundStyle(V2Theme.blue)
            Text(title).foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(V2Theme.ColorRole.surfaceRaised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct V2ProfileEditorView: View {
    @AppStorage("profile.name") private var name = "Sky"
    @AppStorage("profile.subtitle") private var subtitle = "Tough Trial"
    @AppStorage("profile.phone") private var phone = ""
    @AppStorage("profile.email") private var email = ""
    @AppStorage("profile.douyin") private var douyin = ""
    @AppStorage("profile.xiaohongshu") private var xiaohongshu = ""
    @AppStorage("profile.github") private var github = ""
    @AppStorage("profile.x") private var x = ""

    var body: some View {
        Form {
            Section("公开资料") {
                TextField("姓名", text: $name)
                TextField("身份 / 简介", text: $subtitle)
                TextField("手机号", text: $phone)
                TextField("邮箱", text: $email)
            }
            Section {
                TextField("抖音账号或主页链接", text: $douyin)
                TextField("小红书账号或主页链接", text: $xiaohongshu)
                TextField("GitHub 主页链接", text: $github)
                TextField("X 主页链接", text: $x)
            } header: {
                Text("社交媒体")
            } footer: {
                Text("填写账号或链接后，首页会直接提供二维码入口。")
            }
        }
        .navigationTitle("编辑我的资料")
        .v2InlineNavigationTitle()
    }
}

private struct V2SimpleQRCodeView: View {
    let title: String
    let payload: String

    private var qrImage: Image? {
        let value = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }

        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return Image(decorative: cgImage, scale: 1)
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Group {
                if let qrImage {
                    qrImage
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                } else {
                    Image(systemName: "qrcode")
                        .resizable()
                        .scaledToFit()
                        .padding(34)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 220, height: 220)
            .padding(24)
            .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            Text(title).font(.title2.weight(.semibold))
            Text(payload.isEmpty ? "先在编辑页面补充资料" : payload)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .lineLimit(4)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(V2Theme.page)
        .navigationTitle("二维码")
        .v2InlineNavigationTitle()
    }
}
