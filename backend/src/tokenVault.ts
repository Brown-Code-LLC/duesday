import { createCipheriv, createDecipheriv, randomBytes } from "node:crypto";

export interface TokenEnvelope {
  ciphertext: string;
  iv: string;
  tag: string;
  wrappedKey: string;
  wrapIv: string;
  wrapTag: string;
}

function encrypt(key: Buffer, plaintext: Buffer) {
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", key, iv);
  const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  return { ciphertext, iv, tag: cipher.getAuthTag() };
}

function decrypt(key: Buffer, ciphertext: Buffer, iv: Buffer, tag: Buffer) {
  const decipher = createDecipheriv("aes-256-gcm", key, iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(ciphertext), decipher.final()]);
}

export class TokenVault {
  constructor(private readonly keyEncryptionKey: Buffer) {
    if (keyEncryptionKey.length !== 32) throw new Error("KEK must be 32 bytes");
  }

  seal(token: string): TokenEnvelope {
    const dataKey = randomBytes(32);
    const value = encrypt(dataKey, Buffer.from(token, "utf8"));
    const wrapped = encrypt(this.keyEncryptionKey, dataKey);
    return {
      ciphertext: value.ciphertext.toString("base64"),
      iv: value.iv.toString("base64"),
      tag: value.tag.toString("base64"),
      wrappedKey: wrapped.ciphertext.toString("base64"),
      wrapIv: wrapped.iv.toString("base64"),
      wrapTag: wrapped.tag.toString("base64")
    };
  }

  open(envelope: TokenEnvelope): string {
    const dataKey = decrypt(
      this.keyEncryptionKey,
      Buffer.from(envelope.wrappedKey, "base64"),
      Buffer.from(envelope.wrapIv, "base64"),
      Buffer.from(envelope.wrapTag, "base64")
    );
    return decrypt(
      dataKey,
      Buffer.from(envelope.ciphertext, "base64"),
      Buffer.from(envelope.iv, "base64"),
      Buffer.from(envelope.tag, "base64")
    ).toString("utf8");
  }
}
