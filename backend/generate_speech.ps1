Add-Type -AssemblyName System.Speech
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
$synth.SelectVoiceByHints([System.Speech.Synthesis.VoiceGender]::Female)
$synth.Rate = 0
$outputFile = "d:\Projects\Telesales\backend\uploads\recordings\sample_telesales_call.wav"
$synth.SetOutputToWaveFile($outputFile)
$synth.Speak("Hello, good afternoon! I am calling from AskEVA telesales regarding your business inquiry for our call monitoring and CRM software. We saw your interest and would like to confirm your demo. Can we schedule a brief walk-through for your team tomorrow at eleven AM? Perfect, thank you for your time. Have a great day!")
$synth.Dispose()
Write-Host "Audio generated successfully: $outputFile"
