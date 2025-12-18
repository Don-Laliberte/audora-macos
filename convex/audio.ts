import { mutation } from "./_generated/server";

/**
 * Generates an upload URL for audio files.
 * This is called by the Mac app before uploading an audio file.
 * 
 * @returns A URL that can be used to upload a file via HTTP POST
 */
export const generateUploadUrl = mutation({
  args: {},
  handler: async (ctx) => {
    // Generate an upload URL using Convex storage
    const uploadUrl = await ctx.storage.generateUploadUrl();
    return uploadUrl;
  },
});
