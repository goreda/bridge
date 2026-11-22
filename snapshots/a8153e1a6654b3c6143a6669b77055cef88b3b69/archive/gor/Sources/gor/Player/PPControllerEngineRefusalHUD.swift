// Retained actual fallback reason, shared across PPController source splits.
// Lives outside the controller's monolithic file so the station split keeps it intact.
extension PPController {
    func setEngineRefusalHUD(_ line:String?) {spineUI.setEngineRefusalHUD(line)}
}
