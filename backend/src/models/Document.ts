import mongoose, { Document, Schema } from 'mongoose';

export type DocumentFormat = 'pdf' | 'jpg' | 'png' | 'docx' | 'txt';

export interface IDocument extends Document {
  userId: mongoose.Types.ObjectId;
  name: string;
  format: DocumentFormat;
  filePath: string;
  fileSize: number;
  mimeType: string;
  createdAt: Date;
  updatedAt: Date;
}

const documentSchema = new Schema<IDocument>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    name: { type: String, required: true, trim: true },
    format: { type: String, enum: ['pdf', 'jpg', 'png', 'docx', 'txt'], required: true },
    filePath: { type: String, required: true },
    fileSize: { type: Number, required: true },
    mimeType: { type: String, required: true },
  },
  { timestamps: true }
);

export const DocumentModel = mongoose.model<IDocument>('Document', documentSchema);
