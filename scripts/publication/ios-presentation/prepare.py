#!/usr/bin/env python3
"""Prepare an isolated, simulator-only source snapshot for presentation screenshots.

Never changes release source or data. Output is not a functional app or inference test.
"""
from pathlib import Path
import argparse
import subprocess,tarfile,io,json
root=Path(__file__).resolve().parents[3]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output',type=Path,required=True)
args=parser.parse_args(); work=args.output.resolve()
if not work.is_relative_to(root/'.build'):parser.error('Output must be under this repository .build directory')
work.mkdir(parents=True,exist_ok=True)
out=work/'source'
out.mkdir(exist_ok=False)
blob=subprocess.check_output(['git','archive','HEAD','apps/ios','shared','scripts','assets'],cwd=root)
with tarfile.open(fileobj=io.BytesIO(blob)) as t:t.extractall(out,filter='data')
app=out/'apps/ios/OfflineTranslatorApp.swift'
app.write_text('#if !targetEnvironment(simulator)\n#error("Publication fixture must never be built for a physical device")\n#endif\n'+app.read_text())
(out/'Dependencies').symlink_to(root/'Dependencies',target_is_directory=True)
def change(path,old,new):
 p=out/path;s=p.read_text();assert s.count(old)==1,(path,s.count(old));p.write_text(s.replace(old,new))
change('shared/packages/OfflineCore/Sources/OfflineCore/ConversationPipeline.swift', '@MainActor public final class ConversationPipeline: ObservableObject {', '''@MainActor public final class ConversationPipeline: ObservableObject {
    // Presentation-only fixture in an isolated simulator snapshot; never a release source.
    public func publicationFixture() {
        voiceFields.sourceText = "Good afternoon! I'd like to book a room for two. Is breakfast included?"
        voiceFields.translatedText = "Добрый день! Я хотел бы забронировать номер на двоих. Завтрак включён?"
        voiceFields.resolvedSource = .english; voiceFields.resolvedTarget = .russian
        isReady = true; isRecognitionReady = true; hasOriginalRecording = true
    }
''')
change('shared/packages/OfflineCore/Sources/OfflineCore/ConversationPipeline.swift','''    public func recognitionIsReady(for source: SpeechLanguage?, preference: RecognitionPreference? = nil) -> Bool {
''','''    public func recognitionIsReady(for source: SpeechLanguage?, preference: RecognitionPreference? = nil) -> Bool {
        if ProcessInfo.processInfo.environment["KAT_PUBLICATION_FIXTURE"] == "1" { return true }
''')
change('shared/packages/OfflineCore/Sources/OfflineCore/ImageTranslation.swift','@MainActor public final class ImageTranslationSession: ObservableObject {','''@MainActor public final class ImageTranslationSession: ObservableObject {
    public func publicationFixture() {
        blocks = [ImageTextBlock(text: "WELCOME", box: ImageTextBox(x: 0.11, y: 0.27, width: 0.78, height: 0.08)),
                  ImageTextBlock(text: "Breakfast is served from 7:00 to 10:00.", box: ImageTextBox(x: 0.11, y: 0.38, width: 0.78, height: 0.14)),
                  ImageTextBlock(text: "Please leave your key at reception.", box: ImageTextBox(x: 0.11, y: 0.55, width: 0.78, height: 0.14))]
        translated = zip(blocks, ["ДОБРО ПОЖАЛОВАТЬ", "Завтрак подают с 7:00 до 10:00.", "Пожалуйста, оставьте ключ на стойке регистрации."]).map { TranslatedImageBlock(original: $0.0.text, translation: $0.1, box: $0.0.box) }
        ready = true; complete = true; working = false
    }
''')
change('apps/ios/Camera/CameraModel.swift','@MainActor final class CameraModel: ObservableObject {','''@MainActor final class CameraModel: ObservableObject {
    func publicationFixture() {
        source = .english; target = .russian; translation.publicationFixture()
        let size = CGSize(width: 1200, height: 1600)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        frozen = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(red: 1, green: 0.98, blue: 0.94, alpha: 1).setFill(); context.fill(CGRect(origin: .zero, size: size))
            UIColor.darkGray.setStroke(); let border = UIBezierPath(roundedRect: CGRect(x: 70, y: 330, width: 1060, height: 890), cornerRadius: 26); border.lineWidth = 7; border.stroke()
            for block in translation.translated {
                let b = block.box; (block.original as NSString).draw(in: CGRect(x: b.x*1200,y: b.y*1600,width: b.width*1200,height: b.height*1600), withAttributes: [.font:UIFont.systemFont(ofSize:60), .foregroundColor:UIColor.darkGray])
            }
        }
        overlay = CameraOverlay.render(size: size, blocks: translation.translated)
        error = nil; message = nil
    }
''')
change('shared/apple/Conversation/AppModel.swift','''    func loadAutomaticallyIfNeeded() async {
''','''    func loadAutomaticallyIfNeeded() async {
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["KAT_PUBLICATION_FIXTURE"] == "1" { session.publicationFixture(); return }
        #endif
''')
change('shared/apple/Conversation/AppModel.swift','''    var isVoiceReady: Bool {
''','''    var isVoiceReady: Bool {
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["KAT_PUBLICATION_FIXTURE"] == "1" { return true }
        #endif
        return
''')
change('shared/apple/Conversation/AppModel.swift','''    func openCamera() async {
''','''    func openCamera() async {
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["KAT_PUBLICATION_FIXTURE"] == "1" { usingCamera = true; camera.publicationFixture(); return }
        #endif
''')
(work/'fixture-provenance.json').write_text(json.dumps({'sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],text=True,cwd=root).strip(),'method':'isolated simulator presentation state; no ASR/MT or microphone/camera acceptance','sourceRoot':str(out),'modifiedSourceFiles':['ConversationPipeline.swift','ImageTranslation.swift','CameraModel.swift','AppModel.swift']},indent=2))
print(out)
