using System.Security.Cryptography;
using System.Text;

namespace CapsuleApi.Services;

public sealed class SpatialCryptoService
{
    // Ephemeral/deployment master pepper combined with spatial factors to bind ciphertext to physical location
    private static readonly byte[] MasterSecret = Encoding.UTF8.GetBytes("KapsulAR-2209A-SpatialSeal-MasterKey-2026");

    public (string CipherBase64, string NonceBase64, string TagBase64, string SealHashHex) EncryptSpatialPayload(
        string plaintext,
        string capsuleId,
        double lat,
        double lon,
        double headingDeg,
        string visualSignature)
    {
        byte[] key = DeriveSpatialKey(capsuleId, lat, lon, visualSignature);
        byte[] nonce = RandomNumberGenerator.GetBytes(AesGcm.NonceByteSizes.MaxSize); // 12 bytes
        byte[] plainBytes = Encoding.UTF8.GetBytes(plaintext);
        byte[] cipherBytes = new byte[plainBytes.Length];
        byte[] tag = new byte[AesGcm.TagByteSizes.MaxSize]; // 16 bytes

        byte[] aad = BuildAad(capsuleId, visualSignature);
        using var aes = new AesGcm(key, AesGcm.TagByteSizes.MaxSize);
        aes.Encrypt(nonce, plainBytes, cipherBytes, tag, aad);

        string sealHash = ComputeSealHash(capsuleId, lat, lon, headingDeg, visualSignature);
        return (
            Convert.ToBase64String(cipherBytes),
            Convert.ToBase64String(nonce),
            Convert.ToBase64String(tag),
            sealHash
        );
    }

    public string? DecryptSpatialPayload(
        string cipherBase64,
        string nonceBase64,
        string tagBase64,
        string capsuleId,
        double lat,
        double lon,
        string visualSignature)
    {
        try
        {
            byte[] key = DeriveSpatialKey(capsuleId, lat, lon, visualSignature);
            byte[] cipherBytes = Convert.FromBase64String(cipherBase64);
            byte[] nonce = Convert.FromBase64String(nonceBase64);
            byte[] tag = Convert.FromBase64String(tagBase64);
            byte[] plainBytes = new byte[cipherBytes.Length];
            byte[] aad = BuildAad(capsuleId, visualSignature);

            using var aes = new AesGcm(key, AesGcm.TagByteSizes.MaxSize);
            aes.Decrypt(nonce, cipherBytes, tag, plainBytes, aad);
            return Encoding.UTF8.GetString(plainBytes);
        }
        catch
        {
            return null;
        }
    }

    public string ComputeSealHash(string capsuleId, double lat, double lon, double headingDeg, string visualSignature)
    {
        string gh = GeoMath.EncodeGeohash(lat, lon, 7);
        int sector = (((int)Math.Round(headingDeg) % 360 + 360) % 360) / 30; // 30-deg orientation sector
        string raw = $"{capsuleId}|{gh}|{sector}|{visualSignature.ToLowerInvariant()}";
        using var hmac = new HMACSHA256(MasterSecret);
        byte[] hash = hmac.ComputeHash(Encoding.UTF8.GetBytes(raw));
        return Convert.ToHexString(hash)[..16];
    }

    public double ComputeHeadingAlignmentScore(double expectedHeadingDeg, double observedHeadingDeg)
    {
        double diff = Math.Abs(((observedHeadingDeg - expectedHeadingDeg + 540) % 360) - 180);
        // Within +-45 degrees gives high score; full 180 opposite gives 35%
        double score = 100.0 - (diff / 180.0) * 65.0;
        return Math.Round(Math.Clamp(score, 0, 100), 1);
    }

    private static byte[] DeriveSpatialKey(string capsuleId, double lat, double lon, string visualSignature)
    {
        string gh = GeoMath.EncodeGeohash(lat, lon, 7);
        string material = $"{capsuleId}:{gh}:{visualSignature.Trim().ToLowerInvariant()}";
        using var hmac = new HMACSHA256(MasterSecret);
        return hmac.ComputeHash(Encoding.UTF8.GetBytes(material));
    }

    private static byte[] BuildAad(string capsuleId, string visualSignature)
        => Encoding.UTF8.GetBytes($"KapsulAR:{capsuleId}:{visualSignature.Trim().ToLowerInvariant()}");
}
