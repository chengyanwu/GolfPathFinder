
import SwiftUI
import NaturalLanguage
import Speech

let options = ["Wait!",
               "Show Hole One", "Show Hole Two", "Show Hole Three",
               "Hide Hole One", "Hide Hole Two", "Hide Hole Three",
               "Show Bunker", "Hide Bunker",
               "Show Path", "Hide Path",
               "Please say again!"]

class NLP: ObservableObject {
    private func cal_dot(_ a: [Double], _ b: [Double]) -> Double {
        return zip(a, b).map{$0*$1}.reduce(0, +)
    }
    private func cal_mag(_ a: [Double]) -> Double {
        return sqrt(cal_dot(a, a))
    }
    private func cal_cos(_ a: [Double], _ b: [Double]) -> Double {
        return cal_dot(a, b) / (cal_mag(a) * cal_mag(b))
    }
    
    let EMB = NLEmbedding.sentenceEmbedding(for: .english)
    private var emb_options = [[Double]]()
    
    init() {
        for o in options {
            emb_options.append((EMB?.vector(for: o))!)
        }
    }
    func go(_ ins: String) -> (Int, Double, Int, Double, Int, Double) {
        let e = EMB?.vector(for: (ins=="") ? "_" : ins)
        
        var dis = [Double]()
        for o in emb_options {
            dis.append(cal_cos(e!, o))
        }
        let val1 = dis.max()
        let ret1 = val1!>0.45 ? Int(dis.firstIndex(of: val1!)!) : 11
        
        if ret1==11 {
            return (11, 0.0, 0, 0.0, 0, 0.0)
        }
        
        dis[ret1] = -1
        let val2 = dis.max()
        let ret2 = Int(dis.firstIndex(of: val2!)!)
        
        dis[ret2] = -1
        let val3 = dis.max()
        let ret3 = Int(dis.firstIndex(of: val3!)!)
        
        return (ret1, val1!, ret2, val2!, ret3, val3!)
    }
}

class ASR: NSObject, ObservableObject, SFSpeechRecognizerDelegate {
    
    private var nlp = NLP()
    
    private let eng = AVAudioEngine()
    private var node: AVAudioInputNode?
    private var rec: SFSpeechRecognizer?
    private var req: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    
    @Published var ins = "Press the button to start!"
    @Published var is_run = false
    
    public func toggle() -> (Int, Double, Int, Double, Int, Double) {
        var ret: (Int, Double, Int, Double, Int, Double)

        if is_run==false {
            ret = start()
            is_run = true
        } else {
            ret = stop()
            is_run = false
        }
        
        return ret
    }
    public func start() -> (Int, Double, Int, Double, Int, Double) {
        let audio = AVAudioSession.sharedInstance()
        do {
            try audio.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audio.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("=====Error: audio session=====")
        }
        
        node = eng.inputNode
        rec = SFSpeechRecognizer()
        req = SFSpeechAudioBufferRecognitionRequest()
        
        guard let rec = rec,
              rec.isAvailable,
              let req = req,
              let node = node
        else {
            print("=====Error: speech recognition=====")
            return (0, 0.0, 0, 0.0, 0, 0.0)
        }
        rec.delegate = self
        
        let fmt = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: fmt) { (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
            req.append(buffer)
        }
        task = rec.recognitionTask(with: req) { [weak self] result, error in
            self?.ins = result?.bestTranscription.formattedString ?? "Press the button to start!"
        }
        
        eng.prepare()
        do {
            try eng.start()
            is_run = true
        } catch {
            print("=====Error: audio engine=====")
            _ = stop()
        }
        
        return (0, 0.0, 0, 0.0, 0, 0.0)
    }
    public func stop() -> (Int, Double, Int, Double, Int, Double) {
        eng.stop()
        node?.removeTap(onBus: 0)
        task?.cancel()
        
        node=nil; rec=nil; req=nil; task=nil
        is_run = false
        
        let ret = nlp.go(ins)
        
        return ret
    }
    
    public func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if available {
        } else {
            ins = "Press the button to start!"
            _ = stop()
        }
    }
}

struct ContentView: View {
    
    @ObservedObject private var asr = ASR()
    @State private var action1 = 0
    @State private var action2 = 0
    @State private var action3 = 0
    @State private var score1 = 0.0
    @State private var score2 = 0.0
    @State private var score3 = 0.0
    
    var body: some View {
        Text(asr.ins).padding().lineLimit(1).offset(y: -100)
        Text(options[action1]+" / "+String(format: "%.2f", score1)).padding()
        Text(options[action2]+" / "+String(format: "%.2f", score2)).padding()
        Text(options[action3]+" / "+String(format: "%.2f", score3)).padding()
        Button {
            (action1, score1, action2, score2, action3, score3) = asr.toggle()
        } label: {
            Circle().frame(width: 55, height: 55).foregroundColor(asr.is_run ? Color.green : Color.red)
        }.offset(x: 140, y: 200)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
