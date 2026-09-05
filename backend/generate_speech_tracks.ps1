Add-Type -AssemblyName System.Speech

function CreateVoiceTrack($filename, $gender, $text) {
    $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
    $synth.SelectVoiceByHints($gender)
    $synth.Rate = 0
    $outPath = "d:\Projects\Telesales\backend\uploads\recordings\$filename"
    $synth.SetOutputToWaveFile($outPath)
    $synth.Speak($text)
    $synth.Dispose()
    Write-Host "Generated: $outPath"
}

# 1. Varshini / Outbound Telesales Demo Call
CreateVoiceTrack "varshini_telesales_call.wav" ([System.Speech.Synthesis.VoiceGender]::Female) "Hello, good afternoon! This is Varshini calling from AskEVA telesales. I am following up on your recent request regarding our business software and telesales monitoring dashboard. Our platform helps your sales team track live calls, manage CRM leads, and audit call recordings seamlessly. Would tomorrow morning at eleven AM work for a quick fifteen-minute walkthrough? Excellent, I have scheduled the demo. Thank you so much for your time, and have a wonderful day!"

# 2. Outbound Client Follow-up Call
CreateVoiceTrack "outbound_lead_followup.wav" ([System.Speech.Synthesis.VoiceGender]::Female) "Hello! This is AskEVA business solutions calling to confirm your product demo session. We have updated your account in our CRM pipeline and assigned our senior representative to assist you with the integration. Please let us know if you need any additional brochures or pricing documentation sent directly over WhatsApp. Thank you, talk to you soon."

# 3. Inbound Client Inquiry Call
CreateVoiceTrack "inbound_client_inquiry.wav" ([System.Speech.Synthesis.VoiceGender]::Male) "Thank you for contacting the AskEVA telesales support desk. Your call has been connected to an active agent. Please stay on the line while we pull up your account information and lead history. An agent will be with you in just a moment."
