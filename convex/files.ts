import { query } from "./_generated/server";
import { v } from "convex/values";

/**
 * Gets a URL for a stored file by its storage ID.
 * Useful for verifying files were uploaded and getting download URLs.
 */
export const getFileUrl = query({
  args: { storageId: v.id("_storage") },
  handler: async (ctx, args) => {
    return await ctx.storage.getUrl(args.storageId);
  },
});

/**
 * Lists recent file uploads (for debugging/verification).
 * Note: Convex doesn't have a built-in way to list all files,
 * but you can use this to verify a specific file exists.
 */
export const verifyFileExists = query({
  args: { storageId: v.id("_storage") },
  handler: async (ctx, args) => {
    try {
      const url = await ctx.storage.getUrl(args.storageId);
      return { exists: true, url };
    } catch {
      return { exists: false, url: null };
    }
  },
});
