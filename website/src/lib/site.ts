/** Site-wide facts. Numbers and names come from the app repo (ModelCatalog, DESIGN.md). */
export const site = {
  name: "NanthAi Scribe",
  shortName: "Scribe",
  url: "https://scribe.nanthai.tech",
  parent: { name: "NanthAi", url: "https://nanthai.tech" },
  // Launch day: set launched to true and every download button becomes a link to the URLs below.
  launched: false,
  contactEmail: "support@nanthai.tech",
  downloads: { mac: "/download/NanthAi-Scribe.dmg" },
  stores: { iphone: "#app-store-ios" },
  version: "0.1",
  policyDate: "2026-10-18",
  requirements: { mac: "macOS 26 on Apple silicon", iphone: "iOS 26" },
  models: {
    parakeet: { name: "Parakeet language pack", size: "483 MB", credit: "NVIDIA Parakeet TDT 0.6B v3, CC BY 4.0", languages: 25 },
    gemma: { name: "Gemma 4 E2B", size: "4.36 GB", credit: "Google Gemma 4, Apache 2.0" },
    diarizer: { name: "Meeting speakers", size: "13.7 MB", credit: "FluidAudio speaker diarization (pyannote segmentation and WeSpeaker)" },
  },
  maxLanguages: 3,
} as const;

/** Languages the Parakeet pack understands (ScribeCore/ParakeetTranscriber.swift). */
export const parakeetLanguages = [
  "Bulgarian", "Croatian", "Czech", "Danish", "Dutch", "English", "Estonian", "Finnish", "French",
  "German", "Greek", "Hungarian", "Italian", "Latvian", "Lithuanian", "Maltese", "Polish", "Portuguese",
  "Romanian", "Russian", "Slovak", "Slovenian", "Spanish", "Swedish", "Ukrainian",
];

/** Apple language families observed through SpeechTranscriber on 18 October 2026.
 * The app queries regional availability on each device rather than pinning this list. */
export const appleSpeechLanguages = ['Cantonese', 'Chinese', 'English', 'French', 'German', 'Italian', 'Japanese', 'Korean', 'Portuguese', 'Spanish'];
export const dictationLanguages = [...new Set([...appleSpeechLanguages, ...parakeetLanguages])].sort();
