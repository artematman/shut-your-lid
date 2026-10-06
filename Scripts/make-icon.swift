import AppKit
let folder = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
for size in [16,32,64,128,256,512,1024] {
 let image = NSImage(size: NSSize(width: size, height: size))
 image.lockFocus()
 let ctx = NSGraphicsContext.current!.cgContext
 ctx.scaleBy(x: CGFloat(size)/1024, y: CGFloat(size)/1024)
 NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.12, alpha: 1).setFill()
 NSBezierPath(roundedRect: NSRect(x: 30, y: 30, width: 964, height: 964), xRadius: 210, yRadius: 210).fill()
 let lid = NSBezierPath(); lid.move(to: NSPoint(x: 225,y: 570)); lid.line(to: NSPoint(x: 590,y: 700)); lid.line(to: NSPoint(x: 820,y: 430)); lid.line(to: NSPoint(x: 460,y: 310)); lid.close()
 NSColor(calibratedRed: 0.65, green: 0.96, blue: 0.28, alpha: 1).setFill(); lid.fill()
 let edge = NSBezierPath(); edge.move(to: NSPoint(x:225,y:570));edge.line(to: NSPoint(x:225,y:525));edge.line(to:NSPoint(x:460,y:265));edge.line(to:NSPoint(x:820,y:385));edge.line(to:NSPoint(x:820,y:430));edge.line(to:NSPoint(x:460,y:310));edge.close()
 NSColor(calibratedRed:0.37,green:0.58,blue:0.15,alpha:1).setFill();edge.fill()
 let mark = NSBezierPath();mark.move(to:NSPoint(x:490,y:540));mark.line(to:NSPoint(x:540,y:505));mark.line(to:NSPoint(x:590,y:560));mark.lineWidth=27;mark.lineCapStyle = .round;mark.lineJoinStyle = .round
 NSColor(calibratedRed:0.08,green:0.13,blue:0.04,alpha:1).setStroke();mark.stroke()
 image.unlockFocus()
 let rep=NSBitmapImageRep(data:image.tiffRepresentation!)!
 let data=rep.representation(using:.png,properties:[:])!
 for base in [16,32,128,256,512] {
  if size == base { try data.write(to:URL(fileURLWithPath:folder+"/icon_\(base)x\(base).png")) }
  if size == base*2 { try data.write(to:URL(fileURLWithPath:folder+"/icon_\(base)x\(base)@2x.png")) }
 }
}
