package services

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"time"
)

// ffmpegBin devolve o caminho do ffmpeg no PATH ("" se não houver).
func ffmpegBin() string {
	if p, err := exec.LookPath("ffmpeg"); err == nil {
		return p
	}
	return ""
}

// transcodeToOggOpus converte um áudio qualquer (ex.: audio/webm;codecs=opus,
// que é o que o navegador grava) para audio/ogg com codec OPUS — o único
// formato que a WhatsApp Cloud API aceita como MENSAGEM DE VOZ. Usa ffmpeg via
// arquivos temporários. Devolve erro se o ffmpeg não estiver disponível.
func transcodeToOggOpus(data []byte) ([]byte, error) {
	bin := ffmpegBin()
	if bin == "" {
		return nil, fmt.Errorf("ffmpeg indisponível")
	}

	in, err := os.CreateTemp("", "zap-audio-in-*")
	if err != nil {
		return nil, err
	}
	defer os.Remove(in.Name())
	if _, err := in.Write(data); err != nil {
		in.Close()
		return nil, err
	}
	in.Close()

	out := in.Name() + ".ogg"
	defer os.Remove(out)

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// Formato canônico de MENSAGEM DE VOZ do WhatsApp: ogg/opus, MONO, 48 kHz,
	// otimizado para voz. Sem isso, o áudio "chega" mas o WhatsApp não toca.
	var stderr bytes.Buffer
	cmd := exec.CommandContext(ctx, bin, "-y", "-i", in.Name(),
		"-vn", "-ac", "1", "-ar", "48000",
		"-c:a", "libopus", "-b:a", "32k", "-application", "voip",
		"-f", "ogg", out)
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("ffmpeg: %v (%s)", err, stderr.String())
	}
	return os.ReadFile(out)
}
