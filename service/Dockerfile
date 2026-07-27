# Anexa generator service: Node + LibreOffice (headless) for docx -> PDF.
FROM node:20-slim

# LibreOffice Writer for the conversion, plus Carlito — the metric-compatible substitute for
# Calibri, which the anexa templates use — so the rendered PDF matches the office layout.
RUN apt-get update && apt-get install -y --no-install-recommends \
      libreoffice-writer \
      fonts-crosextra-carlito \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm install --omit=dev --no-audit --no-fund

COPY . .

ENV PORT=8080
EXPOSE 8080
CMD ["node", "server.js"]
