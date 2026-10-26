import AppKit
import Foundation
import Security
import Darwin

@_silgen_name("FilmCraftSetSessionEnvironment")
private func setFilmCraftEnvironment(_ port:UnsafePointer<CChar>,_ token:UnsafePointer<CChar>)->Int32

// One credential per macOS login session. Private files, no credentials in logs,
// command arguments, LaunchAgent plist, project data or GitHub packages.
enum FilmCraftSession {
    struct Credential:Codable {let session:UInt32;let boot:String;let token:String}
    static var directory:URL {FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("ArtCraft Sous-titres IA/Connection",isDirectory:true)}
    static func valid(_ token:String)->Bool {token.utf8.count==64 && token.utf8.allSatisfy{(48...57).contains($0)||(65...70).contains($0)||(97...102).contains($0)}}
    static func bootID()->String {
        var size=0
        guard sysctlbyname("kern.bootsessionuuid",nil,&size,nil,0)==0,size>1 else{return "unavailable"}
        var data=[CChar](repeating:0,count:size)
        guard sysctlbyname("kern.bootsessionuuid",&data,&size,nil,0)==0 else{return "unavailable"}
        return String(cString:data)
    }
    static func loginID()throws->UInt32 {
        var id:SecuritySessionId=0,attributes=SessionAttributeBits(rawValue:0)
        guard SessionGetInfo(SecuritySessionId(callerSecuritySession),&id,&attributes)==errSecSuccess else{throw FilmCraftBridgeError.message("La session macOS ne permet pas de préparer la connexion FilmCraft.")};return id
    }
    static func read(directory:URL=directory,session:UInt32?=nil)->String? {
        guard let id=session ?? (try? loginID()),let data=try? Data(contentsOf:directory.appendingPathComponent("credential.json")),let item=try? JSONDecoder().decode(Credential.self,from:data),item.session==id,item.boot==bootID(),valid(item.token) else{return nil};return item.token
    }
    static func credential(directory:URL=directory,session:UInt32?=nil)throws->String {
        let id=try session ?? loginID(),fm=FileManager.default
        try fm.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700]);try fm.setAttributes([.posixPermissions:0o700],ofItemAtPath:directory.path)
        let lock=open(directory.appendingPathComponent("credential.lock").path,O_CREAT|O_RDWR|O_NOFOLLOW,0o600)
        guard lock>=0 else{throw FilmCraftBridgeError.message("Le stockage privé de la connexion FilmCraft est indisponible.")};defer{flock(lock,LOCK_UN);close(lock)}
        guard flock(lock,LOCK_EX)==0 else{throw FilmCraftBridgeError.message("La connexion FilmCraft est déjà en cours de préparation.")}
        if let existing=read(directory:directory,session:id){return existing}
        var bytes=[UInt8](repeating:0,count:32)
        guard SecRandomCopyBytes(kSecRandomDefault,bytes.count,&bytes)==errSecSuccess else{throw FilmCraftBridgeError.message("La connexion sécurisée FilmCraft n’a pas pu être préparée.")}
        let token=bytes.map{String(format:"%02x",$0)}.joined(),url=directory.appendingPathComponent("credential.json")
        try JSONEncoder().encode(Credential(session:id,boot:bootID(),token:token)).write(to:url,options:.atomic);try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
        return token
    }
    static func currentToken()->String? {read()}
    @discardableResult static func configure(registerAgent:Bool=true)throws->String {
        let token=try credential()
        let code=String(FilmCraftBridge.port).withCString{port in token.withCString{setFilmCraftEnvironment(port,$0)}}
        guard code==0 else{throw FilmCraftBridgeError.message("La connexion automatique de FilmCraft n’a pas pu être préparée. Ouvrez-le depuis Timeline FilmCraft.")}
        if registerAgent {try installAgent()}
        return token
    }
    static func installAgent()throws {
        guard let executable=Bundle.main.executableURL else{return}
        let folder=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents",isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let file=folder.appendingPathComponent("local.artcraft.filmcraft-connection.plist")
        let values:[String:Any]=["Label":"local.artcraft.filmcraft-connection","ProgramArguments":[executable.path,"--configure-filmcraft-connection"],"RunAtLoad":true,"ProcessType":"Background"]
        let data=try PropertyListSerialization.data(fromPropertyList:values,format:.xml,options:0),changed=(try? Data(contentsOf:file)) != data
        if changed {try data.write(to:file,options:.atomic)}
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
        func run(_ args:[String])->Int32 {let p=Process();p.executableURL=URL(fileURLWithPath:"/bin/launchctl");p.arguments=args;p.standardOutput=FileHandle.nullDevice;p.standardError=FileHandle.nullDevice;do{try p.run();p.waitUntilExit();return p.terminationStatus}catch{return -1}}
        let target="gui/\(getuid())/local.artcraft.filmcraft-connection"
        if changed {_=run(["bootout",target])}
        // The previous app wrote a plist without loading it; explicitly register it.
        if run(["print",target]) != 0 {guard run(["bootstrap","gui/\(getuid())",file.path])==0 else{throw FilmCraftBridgeError.message("La préparation automatique au démarrage du Mac n’a pas pu être activée.")}}
    }
    static func selfTest()throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("FilmCraftSessionTests-"+UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        func check(_ condition:Bool)throws{if !condition{throw FilmCraftBridgeError.message("Test de connexion sécurisée échoué.")}}
        let a=try credential(directory:root,session:100),b=try credential(directory:root,session:100),c=try credential(directory:root,session:101)
        try check(valid(a)&&a==b&&a != c&&read(directory:root,session:100)==nil&&read(directory:root,session:101)==c)
        try check((try FileManager.default.attributesOfItem(atPath:root.appendingPathComponent("credential.json").path)[.posixPermissions] as? NSNumber)?.intValue==0o600)
        print("FilmCraft credentials: private storage, reuse within login and rotation between logins OK")
    }
}
