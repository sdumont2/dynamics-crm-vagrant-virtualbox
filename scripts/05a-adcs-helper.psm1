# automatedlab.org scripts
# MIT License

# Copyright (c) 2021 Raimund Andrée, Jan-Hendrik Peters

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

#region Internals
#region .net Types
$certStoreTypes = @'
using System;
using System.Runtime.InteropServices;
namespace System.Security.Cryptography.X509Certificates
{
    public class Win32
    {
        [DllImport("crypt32.dll", EntryPoint="CertOpenStore", CharSet=CharSet.Auto, SetLastError=true)]
        public static extern IntPtr CertOpenStore(
            int storeProvider,
            int encodingType,
            IntPtr hcryptProv,
            int flags,
            String pvPara);
        [DllImport("crypt32.dll", EntryPoint="CertCloseStore", CharSet=CharSet.Auto, SetLastError=true)]
        [return : MarshalAs(UnmanagedType.Bool)]
        public static extern bool CertCloseStore(
            IntPtr storeProvider,
            int flags);
    }
    public enum CertStoreLocation
    {
        CERT_SYSTEM_STORE_CURRENT_USER = 0x00010000,
        CERT_SYSTEM_STORE_LOCAL_MACHINE = 0x00020000,
        CERT_SYSTEM_STORE_SERVICES = 0x00050000,
        CERT_SYSTEM_STORE_USERS = 0x00060000
    }
    [Flags]
    public enum CertStoreFlags
    {
        CERT_STORE_NO_CRYPT_RELEASE_FLAG = 0x00000001,
        CERT_STORE_SET_LOCALIZED_NAME_FLAG = 0x00000002,
        CERT_STORE_DEFER_CLOSE_UNTIL_LAST_FREE_FLAG = 0x00000004,
        CERT_STORE_DELETE_FLAG = 0x00000010,
        CERT_STORE_SHARE_STORE_FLAG = 0x00000040,
        CERT_STORE_SHARE_CONTEXT_FLAG = 0x00000080,
        CERT_STORE_MANIFOLD_FLAG = 0x00000100,
        CERT_STORE_ENUM_ARCHIVED_FLAG = 0x00000200,
        CERT_STORE_UPDATE_KEYID_FLAG = 0x00000400,
        CERT_STORE_BACKUP_RESTORE_FLAG = 0x00000800,
        CERT_STORE_READONLY_FLAG = 0x00008000,
        CERT_STORE_OPEN_EXISTING_FLAG = 0x00004000,
        CERT_STORE_CREATE_NEW_FLAG = 0x00002000,
        CERT_STORE_MAXIMUM_ALLOWED_FLAG = 0x00001000
    }
    public enum CertStoreProvider
    {
        CERT_STORE_PROV_MSG                = 1,
        CERT_STORE_PROV_MEMORY             = 2,
        CERT_STORE_PROV_FILE               = 3,
        CERT_STORE_PROV_REG                = 4,
        CERT_STORE_PROV_PKCS7              = 5,
        CERT_STORE_PROV_SERIALIZED         = 6,
        CERT_STORE_PROV_FILENAME_A         = 7,
        CERT_STORE_PROV_FILENAME_W         = 8,
        CERT_STORE_PROV_FILENAME           = CERT_STORE_PROV_FILENAME_W,
        CERT_STORE_PROV_SYSTEM_A           = 9,
        CERT_STORE_PROV_SYSTEM_W           = 10,
        CERT_STORE_PROV_SYSTEM             = CERT_STORE_PROV_SYSTEM_W,
        CERT_STORE_PROV_COLLECTION         = 11,
        CERT_STORE_PROV_SYSTEM_REGISTRY_A  = 12,
        CERT_STORE_PROV_SYSTEM_REGISTRY_W  = 13,
        CERT_STORE_PROV_SYSTEM_REGISTRY    = CERT_STORE_PROV_SYSTEM_REGISTRY_W,
        CERT_STORE_PROV_PHYSICAL_W         = 14,
        CERT_STORE_PROV_PHYSICAL           = CERT_STORE_PROV_PHYSICAL_W,
        CERT_STORE_PROV_SMART_CARD_W       = 15,
        CERT_STORE_PROV_SMART_CARD         = CERT_STORE_PROV_SMART_CARD_W,
        CERT_STORE_PROV_LDAP_W             = 16,
        CERT_STORE_PROV_LDAP               = CERT_STORE_PROV_LDAP_W
    }
}
'@

$pkiInternalsTypes = @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text.RegularExpressions;
namespace Pki
{
    public static class Period
    {
        public static TimeSpan ToTimeSpan(byte[] value)
        {
            var period = BitConverter.ToInt64(value, 0); period /= -10000000;
            return TimeSpan.FromSeconds(period);
        }
        public static byte[] ToByteArray(TimeSpan value)
        {
            var period = value.TotalSeconds;
            period *= -10000000;
            return BitConverter.GetBytes((long)period);
        }
    }
}
namespace Pki.CATemplate
{
    /// <summary>
    /// 2.27 msPKI-Private-Key-Flag Attribute
    /// https://msdn.microsoft.com/en-us/library/cc226547.aspx
    /// </summary>
    [Flags]
    public enum PrivateKeyFlags
    {
        None = 0, //This flag indicates that attestation data is not required when creating the certificate request. It also instructs the server to not add any attestation OIDs to the issued certificate. For more details, see [MS-WCCE] section 3.2.2.6.2.1.4.5.7.
        RequireKeyArchival = 1, //This flag instructs the client to create a key archival certificate request, as specified in [MS-WCCE] sections 3.1.2.4.2.2.2.8 and 3.2.2.6.2.1.4.5.7.
        AllowKeyExport = 16, //This flag instructs the client to allow other applications to copy the private key to a .pfx file, as specified in [PKCS12], at a later time.
        RequireStrongProtection = 32, //This flag instructs the client to use additional protection for the private key.
        RequireAlternateSignatureAlgorithm = 64, //This flag instructs the client to use an alternate signature format. For more details, see [MS-WCCE] section 3.1.2.4.2.2.2.8.
        ReuseKeysRenewal = 128, //This flag instructs the client to use the same key when renewing the certificate.<35>
        UseLegacyProvider = 256, //This flag instructs the client to process the msPKI-RA-Application-Policies attribute as specified in section 2.23.1.<36>
        TrustOnUse = 512, //This flag indicates that attestation based on the user's credentials is to be performed. For more details, see [MS-WCCE] section 3.2.2.6.2.1.4.5.7.
        ValidateCert = 1024, //This flag indicates that attestation based on the hardware certificate of the Trusted Platform Module (TPM) is to be performed. For more details, see [MS-WCCE] section 3.2.2.6.2.1.4.5.7.
        ValidateKey = 2048, //This flag indicates that attestation based on the hardware key of the TPM is to be performed. For more details, see [MS-WCCE] section 3.2.2.6.2.1.4.5.7.
        Preferred = 4096, //This flag informs the client that it SHOULD include attestation data if it is capable of doing so when creating the certificate request. It also instructs the server that attestation may or may not be completed before any certificates can be issued. For more details, see [MS-WCCE] sections 3.1.2.4.2.2.2.8 and 3.2.2.6.2.1.4.5.7.
        Required = 8192, //This flag informs the client that attestation data is required when creating the certificate request. It also instructs the server that attestation must be completed before any certificates can be issued. For more details, see [MS-WCCE] sections 3.1.2.4.2.2.2.8 and 3.2.2.6.2.1.4.5.7.
        WithoutPolicy = 16384, //This flag instructs the server to not add any certificate policy OIDs to the issued certificate even though attestation SHOULD be performed. For more details, see [MS-WCCE] section 3.2.2.6.2.1.4.5.7.
        xxx = 0x000F0000
    }
    [Flags]
    public enum KeyUsage
    {
        DIGITAL_SIGNATURE = 0x80,
        NON_REPUDIATION = 0x40,
        KEY_ENCIPHERMENT = 0x20,
        DATA_ENCIPHERMENT = 0x10,
        KEY_AGREEMENT = 0x8,
        KEY_CERT_SIGN = 0x4,
        CRL_SIGN = 0x2,
        ENCIPHER_ONLY_KEY_USAGE = 0x1,
        DECIPHER_ONLY_KEY_USAGE = (0x80 << 8),
        NO_KEY_USAGE = 0x0
    }
    public enum KeySpec
    {
        KeyExchange = 1, //Keys used to encrypt/decrypt session keys
        Signature = 2 //Keys used to create and verify digital signatures.
    }
    /// <summary>
    /// 2.26 msPKI-Enrollment-Flag Attribute
    /// https://msdn.microsoft.com/en-us/library/cc226546.aspx
    /// </summary>
    [Flags]
    public enum EnrollmentFlags
    {
        None = 0,
        IncludeSymmetricAlgorithms = 1, //This flag instructs the client and server to include a Secure/Multipurpose Internet Mail Extensions (S/MIME) certificate extension, as specified in RFC4262, in the request and in the issued certificate.
        CAManagerApproval = 2, // This flag instructs the CA to put all requests in a pending state.
        KraPublish = 4, // This flag instructs the CA to publish the issued certificate to the key recovery agent (KRA) container in Active Directory.
        DsPublish = 8, // This flag instructs clients and CA servers to append the issued certificate to the userCertificate attribute, as specified in RFC4523, on the user object in Active Directory.
        AutoenrollmentCheckDsCert = 16, // This flag instructs clients not to do autoenrollment for a certificate based on this template if the user's userCertificate attribute (specified in RFC4523) in Active Directory has a valid certificate based on the same template.
        Autoenrollment = 32, //This flag instructs clients to perform autoenrollment for the specified template.
        ReenrollExistingCert = 64, //This flag instructs clients to sign the renewal request using the private key of the existing certificate.
        RequireUserInteraction = 256, // This flag instructs the client to obtain user consent before attempting to enroll for a certificate that is based on the specified template.
        RemoveInvalidFromStore = 1024, // This flag instructs the autoenrollment client to delete any certificates that are no longer needed based on the specific template from the local certificate storage.
        AllowEnrollOnBehalfOf = 2048, //This flag instructs the server to allow enroll on behalf of(EOBO) functionality.
        IncludeOcspRevNoCheck = 4096, // This flag instructs the server to not include revocation information and add the id-pkix-ocsp-nocheck extension, as specified in RFC2560 section 4.2.2.2.1, to the certificate that is issued. Windows Server 2003 - this flag is not supported.
        ReuseKeyTokenFull = 8192, //This flag instructs the client to reuse the private key for a smart card-based certificate renewal if it is unable to create a new private key on the card.Windows XP, Windows Server 2003 - this flag is not supported. NoRevocationInformation 16384 This flag instructs the server to not include revocation information in the issued certificate. Windows Server 2003, Windows Server 2008 - this flag is not supported.
        BasicConstraintsInEndEntityCerts = 32768, //This flag instructs the server to include Basic Constraints extension in the end entity certificates. Windows Server 2003, Windows Server 2008 - this flag is not supported.
        IgnoreEnrollOnReenrollment = 65536, //This flag instructs the CA to ignore the requirement for Enroll permissions on the template when processing renewal requests. Windows Server 2003, Windows Server 2008, Windows Server 2008 R2 - this flag is not supported.
        IssuancePoliciesFromRequest = 131072 //This flag indicates that the certificate issuance policies to be included in the issued certificate come from the request rather than from the template. The template contains a list of all of the issuance policies that the request is allowed to specify; if the request contains policies that are not listed in the template, then the request is rejected. Windows Server 2003, Windows Server 2008, Windows Server 2008 R2 - this flag is not supported.
    }
    /// <summary>
    /// 2.28 msPKI-Certificate-Name-Flag Attribute
    /// https://msdn.microsoft.com/en-us/library/cc226548.aspx
    /// </summary>
    [Flags]
    public enum NameFlags
    {
        EnrolleeSuppliesSubject = 1, //This flag instructs the client to supply subject information in the certificate request
        OldCertSuppliesSubjectAndAltName = 8, //This flag instructs the client to reuse values of subject name and alternative subject name extensions from an existing valid certificate when creating a certificate renewal request. Windows Server 2003, Windows Server 2008 - this flag is not supported.
        EnrolleeSuppluiesAltSubject = 65536, //This flag instructs the client to supply subject alternate name information in the certificate request.
        AltSubjectRequireDomainDNS = 4194304, //This flag instructs the CA to add the value of the requester's FQDN and NetBIOS name to the Subject Alternative Name extension of the issued certificate.
        AltSubjectRequireDirectoryGUID = 16777216, //This flag instructs the CA to add the value of the objectGUID attribute from the requestor's user object in Active Directory to the Subject Alternative Name extension of the issued certificate.
        AltSubjectRequireUPN = 33554432, //This flag instructs the CA to add the value of the UPN attribute from the requestor's user object in Active Directory to the Subject Alternative Name extension of the issued certificate.
        AltSubjectRequireEmail = 67108864, //This flag instructs the CA to add the value of the e-mail attribute from the requestor's user object in Active Directory to the Subject Alternative Name extension of the issued certificate.
        AltSubjectRequireDNS = 134217728, //This flag instructs the CA to add the value obtained from the DNS attribute of the requestor's user object in Active Directory to the Subject Alternative Name extension of the issued certificate.
        SubjectRequireDNSasCN = 268435456, //This flag instructs the CA to add the value obtained from the DNS attribute of the requestor's user object in Active Directory as the CN in the subject of the issued certificate.
        SubjectRequireEmail = 536870912, //This flag instructs the CA to add the value of the e-mail attribute from the requestor's user object in Active Directory as the subject of the issued certificate.
        SubjectRequireCommonName = 1073741824, //This flag instructs the CA to set the subject name to the requestor's CN from Active Directory.
        SubjectrequireDirectoryPath = -2147483648 //This flag instructs the CA to set the subject name to the requestor's distinguished name (DN) from Active Directory.
    }
    /// <summary>
    /// 2.4 flags Attribute
    /// https://msdn.microsoft.com/en-us/library/cc226550.aspx
    /// </summary>
    [Flags]
    public enum Flags
    {
        Undefined = 1, //Undefined.
        AddEmail = 2, //Reserved. All protocols MUST ignore this flag.
        Undefined2 = 4, //Undefined.
        DsPublish = 8, //Reserved. All protocols MUST ignore this flag.
        AllowKeyExport = 16, //Reserved. All protocols MUST ignore this flag.
        Autoenrollment = 32, //This flag indicates whether clients can perform autoenrollment for the specified template.
        MachineType = 64, //This flag indicates that this certificate template is for an end entity that represents a machine.
        IsCA = 128, //This flag indicates a certificate request for a CA certificate.
        AddTemplateName = 512, //This flag indicates that a certificate based on this section needs to include a template name certificate extension.
        DoNotPersistInDB = 1024, //This flag indicates that the record of a certificate request for a certificate that is issued need not be persisted by the CA. Windows Server 2003, Windows Server 2008 - this flag is not supported.
        IsCrossCA = 2048, //This flag indicates a certificate request for cross-certifying a certificate.
        IsDefault = 65536, //This flag indicates that the template SHOULD not be modified in any way.
        IsModified = 131072 //This flag indicates that the template MAY be modified if required.
    }
}
namespace Pki.Certificates
{
    public enum CertificateType
    {
        Cer,
        Pfx
    }
    public class CertificateInfo
    {
        private X509Certificate2 certificate;
        private byte[] rawContentBytes;
        public string ComputerName { get; set; }
        public string Location { get; set; }
        public string ServiceName { get; set; }
        public string Store { get; set; }
        public string Password { get; set; }
        public X509Certificate2 Certificate
        {
            get { return certificate; }
        }
        public List<string> DnsNameList
        {
            get
            {
                return ParseSujectAlternativeNames(Certificate).ToList();
            }
        }
        public string Thumbprint
        {
            get
            {
                return Certificate.Thumbprint;
            }
        }
        public byte[] CertificateBytes
        {
            get
            {
                return certificate.RawData;
            }
        }
        public byte[] RawContentBytes
        {
            get
            {
                return rawContentBytes;
            }
        }
        public CertificateInfo(X509Certificate2 certificate)
        {
            this.certificate = certificate;
            rawContentBytes = new byte[0];
        }
        public CertificateInfo(byte[] bytes)
        {
            rawContentBytes = bytes;
            certificate = new X509Certificate2(rawContentBytes);
        }
        public CertificateInfo(byte[] bytes, SecureString password)
        {
            rawContentBytes = bytes;
            certificate = new X509Certificate2(rawContentBytes, password, X509KeyStorageFlags.Exportable);
            Password = ConvertToString(password);
        }
        public CertificateInfo(string fileName)
        {
            rawContentBytes = File.ReadAllBytes(fileName);
            certificate = new X509Certificate2(rawContentBytes);
        }
        public CertificateInfo(string fileName, SecureString password)
        {
            rawContentBytes = File.ReadAllBytes(fileName);
            certificate = new X509Certificate2(rawContentBytes, password, X509KeyStorageFlags.Exportable);
            Password = ConvertToString(password);
        }
        public X509ContentType Type
        {
            get
            {
                if (rawContentBytes.Length > 0)
                    return X509Certificate2.GetCertContentType(rawContentBytes);
                else
                    return X509Certificate2.GetCertContentType(CertificateBytes);
            }
        }
        public static IEnumerable<string> ParseSujectAlternativeNames(X509Certificate2 cert)
        {
            Regex sanRex = new Regex(@"^DNS Name=(.*)", RegexOptions.Compiled | RegexOptions.CultureInvariant);
            var sanList = from X509Extension ext in cert.Extensions
                          where ext.Oid.FriendlyName.Equals("Subject Alternative Name", StringComparison.Ordinal)
                          let data = new AsnEncodedData(ext.Oid, ext.RawData)
                          let text = data.Format(true)
                          from line in text.Split(new char[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries)
                          let match = sanRex.Match(line)
                          where match.Success && match.Groups.Count > 0 && !string.IsNullOrEmpty(match.Groups[1].Value)
                          select match.Groups[1].Value;
            return sanList;
        }
        private string ConvertToString(SecureString s)
        {
            var bstr = System.Runtime.InteropServices.Marshal.SecureStringToBSTR(s);
            return System.Runtime.InteropServices.Marshal.PtrToStringAuto(bstr);
        }
    }
}
'@

$gpoType = @'
    using System;
    using System.Collections.Generic;
    using System.Runtime.CompilerServices;
    using System.Runtime.InteropServices;
    using System.Text;
    using System.Threading;
    using Microsoft.Win32;
    namespace GPO
    {
        /// <summary>
        /// Represent the result of group policy operations.
        /// </summary>
        public enum ResultCode
        {
            Succeed = 0,
            CreateOrOpenFailed = -1,
            SetFailed = -2,
            SaveFailed = -3
        }
        /// <summary>
        /// The WinAPI handler for GroupPlicy operations.
        /// </summary>
        public class WinAPIForGroupPolicy
        {
            // Group Policy Object open / creation flags
            const UInt32 GPO_OPEN_LOAD_REGISTRY = 0x00000001;    // Load the registry files
            const UInt32 GPO_OPEN_READ_ONLY = 0x00000002;    // Open the GPO as read only
            // Group Policy Object option flags
            const UInt32 GPO_OPTION_DISABLE_USER = 0x00000001;   // The user portion of this GPO is disabled
            const UInt32 GPO_OPTION_DISABLE_MACHINE = 0x00000002;   // The machine portion of this GPO is disabled
            const UInt32 REG_OPTION_NON_VOLATILE = 0x00000000;
            const UInt32 ERROR_MORE_DATA = 234;
            // You can find the Guid in <Gpedit.h>
            static readonly Guid REGISTRY_EXTENSION_GUID = new Guid("35378EAC-683F-11D2-A89A-00C04FBBCFA2");
            static readonly Guid CLSID_GPESnapIn = new Guid("8FC0B734-A0E1-11d1-A7D3-0000F87571E3");
            /// <summary>
            /// Group Policy Object type.
            /// </summary>
            enum GROUP_POLICY_OBJECT_TYPE
            {
                GPOTypeLocal = 0,                       // Default GPO on the local machine
                GPOTypeRemote,                          // GPO on a remote machine
                GPOTypeDS,                              // GPO in the Active Directory
                GPOTypeLocalUser,                       // User-specific GPO on the local machine
                GPOTypeLocalGroup                       // Group-specific GPO on the local machine
            }
            #region COM
            /// <summary>
            /// Group Policy Interface definition from COM.
            /// You can find the Guid in <Gpedit.h>
            /// </summary>
            [Guid("EA502723-A23D-11d1-A7D3-0000F87571E3"),
            InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
            interface IGroupPolicyObject
            {
                void New(
                [MarshalAs(UnmanagedType.LPWStr)] String pszDomainName,
                [MarshalAs(UnmanagedType.LPWStr)] String pszDisplayName,
                UInt32 dwFlags);
                void OpenDSGPO(
                    [MarshalAs(UnmanagedType.LPWStr)] String pszPath,
                    UInt32 dwFlags);
                void OpenLocalMachineGPO(UInt32 dwFlags);
                void OpenRemoteMachineGPO(
                    [MarshalAs(UnmanagedType.LPWStr)] String pszComputerName,
                    UInt32 dwFlags);
                void Save(
                    [MarshalAs(UnmanagedType.Bool)] bool bMachine,
                    [MarshalAs(UnmanagedType.Bool)] bool bAdd,
                    [MarshalAs(UnmanagedType.LPStruct)] Guid pGuidExtension,
                    [MarshalAs(UnmanagedType.LPStruct)] Guid pGuid);
                void Delete();
                void GetName(
                    [MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszName,
                    Int32 cchMaxLength);
                void GetDisplayName(
                    [MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszName,
                    Int32 cchMaxLength);
                void SetDisplayName([MarshalAs(UnmanagedType.LPWStr)] String pszName);
                void GetPath(
                    [MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszPath,
                    Int32 cchMaxPath);
                void GetDSPath(
                    UInt32 dwSection,
                    [MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszPath,
                    Int32 cchMaxPath);
                void GetFileSysPath(
                    UInt32 dwSection,
                    [MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszPath,
                    Int32 cchMaxPath);
                UInt32 GetRegistryKey(UInt32 dwSection);
                Int32 GetOptions();
                void SetOptions(UInt32 dwOptions, UInt32 dwMask);
                void GetType(out GROUP_POLICY_OBJECT_TYPE gpoType);
                void GetMachineName(
                    [MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszName,
                    Int32 cchMaxLength);
                UInt32 GetPropertySheetPages(out IntPtr hPages);
            }
            /// <summary>
            /// Group Policy Class definition from COM.
            /// You can find the Guid in <Gpedit.h>
            /// </summary>
            [ComImport, Guid("EA502722-A23D-11d1-A7D3-0000F87571E3")]
            class GroupPolicyObject { }
            #endregion
            #region WinAPI You can find definition of API for C# on: http://pinvoke.net/
            /// <summary>
            /// Opens the specified registry key. Note that key names are not case sensitive.
            /// </summary>
            /// See http://msdn.microsoft.com/en-us/library/ms724897(VS.85).aspx for more info about the parameters.<br/>
            [DllImport("advapi32.dll", CharSet = CharSet.Auto)]
            public static extern Int32 RegOpenKeyEx(
            UIntPtr hKey,
            String subKey,
            Int32 ulOptions,
            RegSAM samDesired,
            out UIntPtr hkResult);
            /// <summary>
            /// Retrieves the type and data for the specified value name associated with an open registry key.
            /// </summary>
            /// See http://msdn.microsoft.com/en-us/library/ms724911(VS.85).aspx for more info about the parameters and return value.<br/>
            [DllImport("advapi32.dll", CharSet = CharSet.Unicode, EntryPoint = "RegQueryValueExW", SetLastError = true)]
            static extern Int32 RegQueryValueEx(
            UIntPtr hKey,
            String lpValueName,
            Int32 lpReserved,
            out UInt32 lpType,
            [Out] byte[] lpData,
            ref UInt32 lpcbData);
            /// <summary>
            /// Sets the data and type of a specified value under a registry key.
            /// </summary>
            /// See http://msdn.microsoft.com/en-us/library/ms724923(VS.85).aspx for more info about the parameters and return value.<br/>
            [DllImport("advapi32.dll", SetLastError = true)]
            static extern Int32 RegSetValueEx(
            UInt32 hKey,
            [MarshalAs(UnmanagedType.LPStr)] String lpValueName,
            Int32 Reserved,
            Microsoft.Win32.RegistryValueKind dwType,
            IntPtr lpData,
            Int32 cbData);
            /// <summary>
            /// Creates the specified registry key. If the key already exists, the function opens it. Note that key names are not case sensitive.
            /// </summary>
            /// See http://msdn.microsoft.com/en-us/library/ms724844(v=VS.85).aspx for more info about the parameters and return value.<br/>
            [DllImport("advapi32.dll", SetLastError = true)]
            static extern Int32 RegCreateKeyEx(
            UInt32 hKey,
            String lpSubKey,
            UInt32 Reserved,
            String lpClass,
            RegOption dwOptions,
            RegSAM samDesired,
            IntPtr lpSecurityAttributes,
            out UInt32 phkResult,
            out RegResult lpdwDisposition);
            /// <summary>
            /// Closes a handle to the specified registry key.
            /// </summary>
            /// See http://msdn.microsoft.com/en-us/library/ms724837(VS.85).aspx for more info about the parameters and return value.<br/>
            [DllImport("advapi32.dll", SetLastError = true)]
            static extern Int32 RegCloseKey(
            UInt32 hKey);
            /// <summary>
            /// Deletes a subkey and its values from the specified platform-specific view of the registry. Note that key names are not case sensitive.
            /// </summary>
            /// See http://msdn.microsoft.com/en-us/library/ms724847(VS.85).aspx for more info about the parameters and return value.<br/>
            [DllImport("advapi32.dll", EntryPoint = "RegDeleteKeyEx", SetLastError = true)]
            public static extern Int32 RegDeleteKeyEx(
            UInt32 hKey,
            String lpSubKey,
            RegSAM samDesired,
            UInt32 Reserved);
            #endregion
            /// <summary>
            /// Registry creating volatile check.
            /// </summary>
            [Flags]
            public enum RegOption
            {
                NonVolatile = 0x0,
                Volatile = 0x1,
                CreateLink = 0x2,
                BackupRestore = 0x4,
                OpenLink = 0x8
            }
            /// <summary>
            /// Access mask the specifies the platform-specific view of the registry.
            /// </summary>
            [Flags]
            public enum RegSAM
            {
                QueryValue = 0x00000001,
                SetValue = 0x00000002,
                CreateSubKey = 0x00000004,
                EnumerateSubKeys = 0x00000008,
                Notify = 0x00000010,
                CreateLink = 0x00000020,
                WOW64_32Key = 0x00000200,
                WOW64_64Key = 0x00000100,
                WOW64_Res = 0x00000300,
                Read = 0x00020019,
                Write = 0x00020006,
                Execute = 0x00020019,
                AllAccess = 0x000f003f
            }
            /// <summary>
            /// Structure for security attributes.
            /// </summary>
            [StructLayout(LayoutKind.Sequential)]
            public struct SECURITY_ATTRIBUTES
            {
                public Int32 nLength;
                public IntPtr lpSecurityDescriptor;
                public Int32 bInheritHandle;
            }
            /// <summary>
            /// Flag returned by calling RegCreateKeyEx.
            /// </summary>
            public enum RegResult
            {
                CreatedNewKey = 0x00000001,
                OpenedExistingKey = 0x00000002
            }
            /// <summary>
            /// Class to create an object to handle the group policy operation.
            /// </summary>
            public class GroupPolicyObjectHandler
            {
                public const Int32 REG_NONE = 0;
                public const Int32 REG_SZ = 1;
                public const Int32 REG_EXPAND_SZ = 2;
                public const Int32 REG_BINARY = 3;
                public const Int32 REG_DWORD = 4;
                public const Int32 REG_DWORD_BIG_ENDIAN = 5;
                public const Int32 REG_MULTI_SZ = 7;
                public const Int32 REG_QWORD = 11;
                // Group Policy interface handler
                IGroupPolicyObject iGroupPolicyObject;
                // Group Policy object handler.
                GroupPolicyObject groupPolicyObject;
                #region constructor
                /// <summary>
                /// Constructor.
                /// </summary>
                /// <param name="remoteMachineName">Target machine name to operate group policy</param>
                /// <exception cref="System.Runtime.InteropServices.COMException">Throw when com execution throws exceptions</exception>
                public GroupPolicyObjectHandler(String remoteMachineName)
                {
                    groupPolicyObject = new GroupPolicyObject();
                    iGroupPolicyObject = (IGroupPolicyObject)groupPolicyObject;
                    try
                    {
                        if (String.IsNullOrEmpty(remoteMachineName))
                        {
                            iGroupPolicyObject.OpenLocalMachineGPO(GPO_OPEN_LOAD_REGISTRY);
                        }
                        else
                        {
                            iGroupPolicyObject.OpenRemoteMachineGPO(remoteMachineName, GPO_OPEN_LOAD_REGISTRY);
                        }
                    }
                    catch (COMException e)
                    {
                        throw e;
                    }
                }
                #endregion
                #region interface related methods
                /// <summary>
                /// Retrieves the display name for the GPO.
                /// </summary>
                /// <returns>Display name</returns>
                /// <exception cref="System.Runtime.InteropServices.COMException">Throw when com execution throws exceptions</exception>
                public String GetDisplayName()
                {
                    StringBuilder pszName = new StringBuilder(Byte.MaxValue);
                    try
                    {
                        iGroupPolicyObject.GetDisplayName(pszName, Byte.MaxValue);
                    }
                    catch (COMException e)
                    {
                        throw e;
                    }
                    return pszName.ToString();
                }
                /// <summary>
                /// Retrieves the computer name of the remote GPO.
                /// </summary>
                /// <returns>Machine name</returns>
                /// <exception cref="System.Runtime.InteropServices.COMException">Throw when com execution throws exceptions</exception>
                public String GetMachineName()
                {
                    StringBuilder pszName = new StringBuilder(Byte.MaxValue);
                    try
                    {
                        iGroupPolicyObject.GetMachineName(pszName, Byte.MaxValue);
                    }
                    catch (COMException e)
                    {
                        throw e;
                    }
                    return pszName.ToString();
                }
                /// <summary>
                /// Retrieves the options for the GPO.
                /// </summary>
                /// <returns>Options flag</returns>
                /// <exception cref="System.Runtime.InteropServices.COMException">Throw when com execution throws exceptions</exception>
                public Int32 GetOptions()
                {
                    try
                    {
                        return iGroupPolicyObject.GetOptions();
                    }
                    catch (COMException e)
                    {
                        throw e;
                    }
                }
                /// <summary>
                /// Retrieves the path to the GPO.
                /// </summary>
                /// <returns>The path to the GPO</returns>
                /// <exception cref="System.Runtime.InteropServices.COMException">Throw when com execution throws exceptions</exception>
                public String GetPath()
                {
                    StringBuilder pszName = new StringBuilder(Byte.MaxValue);
                    try
                    {
                        iGroupPolicyObject.GetPath(pszName, Byte.MaxValue);
                    }
                    catch (COMException e)
                    {
                        throw e;
                    }
                    return pszName.ToString();
                }
                /// <summary>
                /// Retrieves a handle to the root of the registry key for the machine section.
                /// </summary>
                /// <returns>A handle to the root of the registry key for the specified GPO computer section</returns>
                /// <exception cref="System.Runtime.InteropServices.COMException">Throw when com execution throws exceptions</exception>
                public UInt32 GetMachineRegistryKey()
                {
                    UInt32 handle;
                    try
                    {
                        handle = iGroupPolicyObject.GetRegistryKey(GPO_OPTION_DISABLE_MACHINE);
                    }
                    catch (COMException e)
                    {
                        throw e;
                    }
                    return handle;
                }
                /// <summary>
                /// Retrieves a handle to the root of the registry key for the user section.
                /// </summary>
                /// <returns>A handle to the root of the registry key for the specified GPO user section</returns>
                /// <exception cref="System.Runtime.InteropServices.COMException">Throw when com execution throws exceptions</exception>
                public UInt32 GetUserRegistryKey()
                {
                    UInt32 handle;
                    try
                    {
                        handle = iGroupPolicyObject.GetRegistryKey(GPO_OPTION_DISABLE_USER);
                    }
                    catch (COMException e)
                    {
                        throw e;
                    }
                    return handle;
                }
                /// <summary>
                /// Saves the specified registry policy settings to disk and updates the revision number of the GPO.
                /// </summary>
                /// <param name="isMachine">Specifies the registry policy settings to be saved. If this parameter is TRUE, the computer policy settings are saved. Otherwise, the user policy settings are saved.</param>
                /// <param name="isAdd">Specifies whether this is an add or delete operation. If this parameter is FALSE, the last policy setting for the specified extension pGuidExtension is removed. In all other cases, this parameter is TRUE.</param>
                /// <exception cref="System.Runtime.InteropServices.COMException">Throw when com execution throws exceptions</exception>
                public void Save(bool isMachine, bool isAdd)
                {
                    try
                    {
                        iGroupPolicyObject.Save(isMachine, isAdd, REGISTRY_EXTENSION_GUID, CLSID_GPESnapIn);
                    }
                    catch (COMException e)
                    {
                        throw e;
                    }
                }
                #endregion
                #region customized methods
                /// <summary>
                /// Set the group policy value.
                /// </summary>
                /// <param name="isMachine">Specifies the registry policy settings to be saved. If this parameter is TRUE, the computer policy settings are saved. Otherwise, the user policy settings are saved.</param>
                /// <param name="subKey">Group policy config full path</param>
                /// <param name="valueName">Group policy config key name</param>
                /// <param name="value">If value is null, it will envoke the delete method</param>
                /// <returns>Whether the config is successfully set</returns>
                public ResultCode SetGroupPolicy(bool isMachine, String subKey, String valueName, object value)
                {
                    UInt32 gphKey = (isMachine) ? GetMachineRegistryKey() : GetUserRegistryKey();
                    UInt32 gphSubKey;
                    UIntPtr hKey;
                    RegResult flag;
                    if (null == value)
                    {
                        // check the key's existance
                        if (RegOpenKeyEx((UIntPtr)gphKey, subKey, 0, RegSAM.QueryValue, out hKey) == 0)
                        {
                            RegCloseKey((UInt32)hKey);
                            // delete the GPO
                            Int32 hr = RegDeleteKeyEx(
                            gphKey,
                            subKey,
                            RegSAM.Write,
                            0);
                            if (0 != hr)
                            {
                                RegCloseKey(gphKey);
                                return ResultCode.CreateOrOpenFailed;
                            }
                            Save(isMachine, false);
                        }
                        else
                        {
                            // not exist
                        }
                    }
                    else
                    {
                        // set the GPO
                        Int32 hr = RegCreateKeyEx(
                        gphKey,
                        subKey,
                        0,
                        null,
                        RegOption.NonVolatile,
                        RegSAM.Write,
                        IntPtr.Zero,
                        out gphSubKey,
                        out flag);
                        if (0 != hr)
                        {
                            RegCloseKey(gphSubKey);
                            RegCloseKey(gphKey);
                            return ResultCode.CreateOrOpenFailed;
                        }
                        Int32 cbData = 4;
                        IntPtr keyValue = IntPtr.Zero;
                        if (value.GetType() == typeof(Int32))
                        {
                            keyValue = Marshal.AllocHGlobal(cbData);
                            Marshal.WriteInt32(keyValue, (Int32)value);
                            hr = RegSetValueEx(gphSubKey, valueName, 0, RegistryValueKind.DWord, keyValue, cbData);
                        }
                        else if (value.GetType() == typeof(String))
                        {
                            keyValue = Marshal.StringToHGlobalAnsi(value.ToString());
                            cbData = System.Text.Encoding.UTF8.GetByteCount(value.ToString()) + 1;
                            hr = RegSetValueEx(gphSubKey, valueName, 0, RegistryValueKind.String, keyValue, cbData);
                        }
                        else
                        {
                            RegCloseKey(gphSubKey);
                            RegCloseKey(gphKey);
                            return ResultCode.SetFailed;
                        }
                        if (0 != hr)
                        {
                            RegCloseKey(gphSubKey);
                            RegCloseKey(gphKey);
                            return ResultCode.SetFailed;
                        }
                        try
                        {
                            Save(isMachine, true);
                        }
                        catch (COMException e)
                        {
                            RegCloseKey(gphSubKey);
                            RegCloseKey(gphKey);
                            return ResultCode.SaveFailed;
                        }
                        RegCloseKey(gphSubKey);
                        RegCloseKey(gphKey);
                    }
                    return ResultCode.Succeed;
                }
                /// <summary>
                /// Get the config of the group policy.
                /// </summary>
                /// <param name="isMachine">Specifies the registry policy settings to be saved. If this parameter is TRUE, get from the computer policy settings. Otherwise, get from the user policy settings.</param>
                /// <param name="subKey">Group policy config full path</param>
                /// <param name="valueName">Group policy config key name</param>
                /// <returns>The setting of the specified config</returns>
                public object GetGroupPolicy(bool isMachine, String subKey, String valueName)
                {
                    UIntPtr gphKey = (UIntPtr)((isMachine) ? GetMachineRegistryKey() : GetUserRegistryKey());
                    UIntPtr hKey;
                    object keyValue = null;
                    UInt32 size = 1;
                    if (RegOpenKeyEx(gphKey, subKey, 0, RegSAM.QueryValue, out hKey) == 0)
                    {
                        UInt32 type;
                        byte[] data = new byte[size];  // to store retrieved the value's data
                        if (RegQueryValueEx(hKey, valueName, 0, out type, data, ref size) == 234)
                        {
                            //size retreived
                            data = new byte[size]; //redefine data
                        }
                        if (RegQueryValueEx(hKey, valueName, 0, out type, data, ref size) != 0)
                        {
                            return null;
                        }
                        switch (type)
                        {
                            case REG_NONE:
                            case REG_BINARY:
                                keyValue = data;
                                break;
                            case REG_DWORD:
                                keyValue = (((data[0] | (data[1] << 8)) | (data[2] << 16)) | (data[3] << 24));
                                break;
                            case REG_DWORD_BIG_ENDIAN:
                                keyValue = (((data[3] | (data[2] << 8)) | (data[1] << 16)) | (data[0] << 24));
                                break;
                            case REG_QWORD:
                                {
                                    UInt32 numLow = (UInt32)(((data[0] | (data[1] << 8)) | (data[2] << 16)) | (data[3] << 24));
                                    UInt32 numHigh = (UInt32)(((data[4] | (data[5] << 8)) | (data[6] << 16)) | (data[7] << 24));
                                    keyValue = (long)(((ulong)numHigh << 32) | (ulong)numLow);
                                    break;
                                }
                            case REG_SZ:
                                var s = Encoding.Unicode.GetString(data, 0, (Int32)size);
                                keyValue = s.Substring(0, s.Length - 1);
                                break;
                            case REG_EXPAND_SZ:
                                keyValue = Environment.ExpandEnvironmentVariables(Encoding.Unicode.GetString(data, 0, (Int32)size));
                                break;
                            case REG_MULTI_SZ:
                                {
                                    List<string> strings = new List<String>();
                                    String packed = Encoding.Unicode.GetString(data, 0, (Int32)size);
                                    Int32 start = 0;
                                    Int32 end = packed.IndexOf("", start);
                                    while (end > start)
                                    {
                                        strings.Add(packed.Substring(start, end - start));
                                        start = end + 1;
                                        end = packed.IndexOf("", start);
                                    }
                                    keyValue = strings.ToArray();
                                    break;
                                }
                            default:
                                throw new NotSupportedException();
                        }
                        RegCloseKey((UInt32)hKey);
                    }
                    return keyValue;
                }
                #endregion
            }
        }
        public class Helper
        {
            private static object _returnValueFromSet, _returnValueFromGet;
            /// <summary>
            /// Set policy config
            /// It will start a single thread to set group policy.
            /// </summary>
            /// <param name="isMachine">Whether is machine config</param>
            /// <param name="configFullPath">The full path configuration</param>
            /// <param name="configKey">The configureation key name</param>
            /// <param name="value">The value to set, boxed with proper type [ String, Int32 ]</param>
            /// <returns>Whether the config is successfully set</returns>
            [MethodImplAttribute(MethodImplOptions.Synchronized)]
            public static ResultCode SetGroupPolicy(bool isMachine, String configFullPath, String configKey, object value)
            {
                Thread worker = new Thread(SetGroupPolicy);
                worker.SetApartmentState(ApartmentState.STA);
                worker.Start(new object[] { isMachine, configFullPath, configKey, value });
                worker.Join();
                return (ResultCode)_returnValueFromSet;
            }
            /// <summary>
            /// Thread start for seting group policy.
            /// Called by public static ResultCode SetGroupPolicy(bool isMachine, WinRMGPConfigName configName, object value)
            /// </summary>
            /// <param name="values">
            /// values[0] - isMachine<br/>
            /// values[1] - configFullPath<br/>
            /// values[2] - configKey<br/>
            /// values[3] - value<br/>
            /// </param>
            private static void SetGroupPolicy(object values)
            {
                object[] valueList = (object[])values;
                bool isMachine = (bool)valueList[0];
                String configFullPath = (String)valueList[1];
                String configKey = (String)valueList[2];
                object value = valueList[3];
                WinAPIForGroupPolicy.GroupPolicyObjectHandler gpHandler = new WinAPIForGroupPolicy.GroupPolicyObjectHandler(null);
                _returnValueFromSet = gpHandler.SetGroupPolicy(isMachine, configFullPath, configKey, value);
            }
            /// <summary>
            /// Get policy config.
            /// It will start a single thread to get group policy
            /// </summary>
            /// <param name="isMachine">Whether is machine config</param>
            /// <param name="configFullPath">The full path configuration</param>
            /// <param name="configKey">The configureation key name</param>
            /// <returns>The group policy setting</returns>
            [MethodImplAttribute(MethodImplOptions.Synchronized)]
            public static object GetGroupPolicy(bool isMachine, String configFullPath, String configKey)
            {
                Thread worker = new Thread(GetGroupPolicy);
                worker.SetApartmentState(ApartmentState.STA);
                worker.Start(new object[] { isMachine, configFullPath, configKey });
                worker.Join();
                return _returnValueFromGet;
            }
            /// <summary>
            /// Thread start for geting group policy.
            /// Called by public static object GetGroupPolicy(bool isMachine, WinRMGPConfigName configName)
            /// </summary>
            /// <param name="values">
            /// values[0] - isMachine<br/>
            /// values[1] - configFullPath<br/>
            /// values[2] - configKey<br/>
            /// </param>
            public static void GetGroupPolicy(object values)
            {
                object[] valueList = (object[])values;
                bool isMachine = (bool)valueList[0];
                String configFullPath = (String)valueList[1];
                String configKey = (String)valueList[2];
                WinAPIForGroupPolicy.GroupPolicyObjectHandler gpHandler = new WinAPIForGroupPolicy.GroupPolicyObjectHandler(null);
                _returnValueFromGet = gpHandler.GetGroupPolicy(isMachine, configFullPath, configKey);
            }
        }
    }
'@
#endregion .net Types

$ApplicationPolicies = @{
    # Remote Desktop
    'Remote Desktop'                            = '1.3.6.1.4.1.311.54.1.2'
    # Windows Update
    'Windows Update'                            = '1.3.6.1.4.1.311.76.6.1'
    # Windows Third Party Applicaiton Component
    'Windows Third Party Application Component' = '1.3.6.1.4.1.311.10.3.25'
    # Windows TCB Component
    'Windows TCB Component'                     = '1.3.6.1.4.1.311.10.3.23'
    # Windows Store
    'Windows Store'                             = '1.3.6.1.4.1.311.76.3.1'
    # Windows Software Extension verification
    ' Windows Software Extension Verification'  = '1.3.6.1.4.1.311.10.3.26'
    # Windows RT Verification
    'Windows RT Verification'                   = '1.3.6.1.4.1.311.10.3.21'
    # Windows Kits Component
    'Windows Kits Component'                    = '1.3.6.1.4.1.311.10.3.20'
    # ROOT_PROGRAM_NO_OCSP_FAILOVER_TO_CRL
    'No OCSP Failover to CRL'                   = '1.3.6.1.4.1.311.60.3.3'
    # ROOT_PROGRAM_AUTO_UPDATE_END_REVOCATION
    'Auto Update End Revocation'                = '1.3.6.1.4.1.311.60.3.2'
    # ROOT_PROGRAM_AUTO_UPDATE_CA_REVOCATION
    'Auto Update CA Revocation'                 = '1.3.6.1.4.1.311.60.3.1'
    # Revoked List Signer
    'Revoked List Signer'                       = '1.3.6.1.4.1.311.10.3.19'
    # Protected Process Verification
    'Protected Process Verification'            = '1.3.6.1.4.1.311.10.3.24'
    # Protected Process Light Verification
    'Protected Process Light Verification'      = '1.3.6.1.4.1.311.10.3.22'
    # Platform Certificate
    'Platform Certificate'                      = '2.23.133.8.2'
    # Microsoft Publisher
    'Microsoft Publisher'                       = '1.3.6.1.4.1.311.76.8.1'
    # Kernel Mode Code Signing
    'Kernel Mode Code Signing'                  = '1.3.6.1.4.1.311.6.1.1'
    # HAL Extension
    'HAL Extension'                             = '1.3.6.1.4.1.311.61.5.1'
    # Endorsement Key Certificate
    'Endorsement Key Certificate'               = '2.23.133.8.1'
    # Early Launch Antimalware Driver
    'Early Launch Antimalware Driver'           = '1.3.6.1.4.1.311.61.4.1'
    # Dynamic Code Generator
    'Dynamic Code Generator'                    = '1.3.6.1.4.1.311.76.5.1'
    # Domain Name System (DNS) Server Trust
    'DNS Server Trust'                          = '1.3.6.1.4.1.311.64.1.1'
    # Document Encryption
    'Document Encryption'                       = '1.3.6.1.4.1.311.80.1'
    # Disallowed List
    'Disallowed List'                           = '1.3.6.1.4.1.10.3.30'
    # Attestation Identity Key Certificate
    # System Health Authentication
    'System Health Authentication'              = '1.3.6.1.4.1.311.47.1.1'
    # Smartcard Logon
    'IdMsKpScLogon'                             = '1.3.6.1.4.1.311.20.2.2'
    # Certificate Request Agent
    'ENROLLMENT_AGENT'                          = '1.3.6.1.4.1.311.20.2.1'
    # CTL Usage
    'AUTO_ENROLL_CTL_USAGE'                     = '1.3.6.1.4.1.311.20.1'
    # Private Key Archival
    'KP_CA_EXCHANGE'                            = '1.3.6.1.4.1.311.21.5'
    # Key Recovery Agent
    'KP_KEY_RECOVERY_AGENT'                     = '1.3.6.1.4.1.311.21.6'
    # Secure Email
    'PKIX_KP_EMAIL_PROTECTION'                  = '1.3.6.1.5.5.7.3.4'
    # IP Security End System
    'PKIX_KP_IPSEC_END_SYSTEM'                  = '1.3.6.1.5.5.7.3.5'
    # IP Security Tunnel Termination
    'PKIX_KP_IPSEC_TUNNEL'                      = '1.3.6.1.5.5.7.3.6'
    # IP Security User
    'PKIX_KP_IPSEC_USER'                        = '1.3.6.1.5.5.7.3.7'
    # Time Stamping
    'PKIX_KP_TIMESTAMP_SIGNING'                 = '1.3.6.1.5.5.7.3.8'
    # OCSP Signing
    'KP_OCSP_SIGNING'                           = '1.3.6.1.5.5.7.3.9'
    # IP security IKE intermediate
    'IPSEC_KP_IKE_INTERMEDIATE'                 = '1.3.6.1.5.5.8.2.2'
    # Microsoft Trust List Signing
    'KP_CTL_USAGE_SIGNING'                      = '1.3.6.1.4.1.311.10.3.1'
    # Microsoft Time Stamping
    'KP_TIME_STAMP_SIGNING'                     = '1.3.6.1.4.1.311.10.3.2'
    # Windows Hardware Driver Verification
    'WHQL_CRYPTO'                               = '1.3.6.1.4.1.311.10.3.5'
    # Windows System Component Verification
    'NT5_CRYPTO'                                = '1.3.6.1.4.1.311.10.3.6'
    # OEM Windows System Component Verification
    'OEM_WHQL_CRYPTO'                           = '1.3.6.1.4.1.311.10.3.7'
    # Embedded Windows System Component Verification
    'EMBEDDED_NT_CRYPTO'                        = '1.3.6.1.4.1.311.10.3.8'
    # Root List Signer
    'ROOT_LIST_SIGNER'                          = '1.3.6.1.4.1.311.10.3.9'
    # Qualified Subordination
    'KP_QUALIFIED_SUBORDINATION'                = '1.3.6.1.4.1.311.10.3.10'
    # Key Recovery
    'KP_KEY_RECOVERY'                           = '1.3.6.1.4.1.311.10.3.11'
    # Document Signing
    'KP_DOCUMENT_SIGNING'                       = '1.3.6.1.4.1.311.10.3.12'
    # Lifetime Signing
    'KP_LIFETIME_SIGNING'                       = '1.3.6.1.4.1.311.10.3.13'
    'DRM'                                       = '1.3.6.1.4.1.311.10.5.1'
    'DRM_INDIVIDUALIZATION'                     = '1.3.6.1.4.1.311.10.5.2'
    # Key Pack Licenses
    'LICENSES'                                  = '1.3.6.1.4.1.311.10.6.1'
    # License Server Verification
    'LICENSE_SERVER'                            = '1.3.6.1.4.1.311.10.6.2'
    'Server Authentication'                     = '1.3.6.1.5.5.7.3.1' #The certificate can be used for OCSP authentication.            
    KP_IPSEC_USER                               = '1.3.6.1.5.5.7.3.7' #The certificate can be used for an IPSEC user.            
    'Code Signing'                              = '1.3.6.1.5.5.7.3.3' #The certificate can be used for signing code.
    'Client Authentication'                     = '1.3.6.1.5.5.7.3.2' #The certificate can be used for authenticating a client.
    KP_EFS                                      = '1.3.6.1.4.1.311.10.3.4' #The certificate can be used to encrypt files by using the Encrypting File System.
    EFS_RECOVERY                                = '1.3.6.1.4.1.311.10.3.4.1' #The certificate can be used for recovery of documents protected by using Encrypting File System (EFS).
    DS_EMAIL_REPLICATION                        = '1.3.6.1.4.1.311.21.19' #The certificate can be used for Directory Service email replication.         
    ANY_APPLICATION_POLICY                      = '1.3.6.1.4.1.311.10.12.1' #The applications that can use the certificate are not restricted.
}
function New-CATemplate
{
    [cmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TemplateName,
        
        [string]$DisplayName,
        
        [Parameter(Mandatory = $true)]
        [string]$SourceTemplateName,
        
        [ValidateSet('EFS_RECOVERY', 'Auto Update CA Revocation', 'No OCSP Failover to CRL', 'OEM_WHQL_CRYPTO', 'Windows TCB Component', 'DNS Server Trust', 'Windows Third Party Application Component', 'ANY_APPLICATION_POLICY', 'KP_LIFETIME_SIGNING', 'Disallowed List', 'DS_EMAIL_REPLICATION', 'LICENSE_SERVER', 'KP_KEY_RECOVERY', 'Windows Kits Component', 'AUTO_ENROLL_CTL_USAGE', 'PKIX_KP_TIMESTAMP_SIGNING', 'Windows Update', 'Document Encryption', 'KP_CTL_USAGE_SIGNING', 'IPSEC_KP_IKE_INTERMEDIATE', 'PKIX_KP_IPSEC_TUNNEL', 'Code Signing', 'KP_KEY_RECOVERY_AGENT', 'KP_QUALIFIED_SUBORDINATION', 'Early Launch Antimalware Driver', 'Remote Desktop', 'WHQL_CRYPTO', 'EMBEDDED_NT_CRYPTO', 'System Health Authentication', 'DRM', 'PKIX_KP_EMAIL_PROTECTION', 'KP_TIME_STAMP_SIGNING', 'Protected Process Light Verification', 'Endorsement Key Certificate', 'KP_IPSEC_USER', 'PKIX_KP_IPSEC_END_SYSTEM', 'LICENSES', 'Protected Process Verification', 'IdMsKpScLogon', 'HAL Extension', 'KP_OCSP_SIGNING', 'Server Authentication', 'Auto Update End Revocation', 'KP_EFS', 'KP_DOCUMENT_SIGNING', 'Windows Store', 'Kernel Mode Code Signing', 'ENROLLMENT_AGENT', 'ROOT_LIST_SIGNER', 'Windows RT Verification', 'NT5_CRYPTO', 'Revoked List Signer', 'Microsoft Publisher', 'Platform Certificate', ' Windows Software Extension Verification', 'KP_CA_EXCHANGE', 'PKIX_KP_IPSEC_USER', 'Dynamic Code Generator', 'Client Authentication', 'DRM_INDIVIDUALIZATION')]
        [string[]]$ApplicationPolicy,

        [Pki.CATemplate.EnrollmentFlags]$EnrollmentFlags = 'None',

        [Pki.CATemplate.PrivateKeyFlags]$PrivateKeyFlags = 0,

        [Pki.CATemplate.KeyUsage]$KeyUsage = 0,
        
        [int]$Version,

        [timespan]$ValidityPeriod,
        
        [timespan]$RenewalPeriod
    )

    $configNc = ([adsi]'LDAP://RootDSE').ConfigurationNamingContext
    $templateContainer = [adsi]"LDAP://CN=Certificate Templates,CN=Public Key Services,CN=Services,$configNc"
    Write-Verbose "Template container is '$templateContainer'"

    $sourceTemplate = $templateContainer.Children | Where-Object Name -eq $SourceTemplateName
    if (-not $sourceTemplate)
    {
        Write-Error "The source template '$SourceTemplateName' could not be found"
        return
    }

    if (($templateContainer.Children | Where-Object Name -eq $TemplateName))
    {
        Write-Error "The template '$TemplateName' does aleady exist"
        return
    }
    
    if (-not $DisplayName) { $DisplayName = $TemplateName }
    
    $newCertTemplate = $templateContainer.Create('pKICertificateTemplate', "CN=$TemplateName") 
    $newCertTemplate.put('distinguishedName', "CN=$TemplateName,CN=Certificate Templates,CN=Public Key Services,CN=Services,$configNc")

    $lastOid = $templateContainer.Children | 
        Sort-Object -Property { [int]($_.'msPKI-Cert-Template-OID' -split '\.')[-1] } | 
        Select-Object -Last 1 -ExpandProperty msPKI-Cert-Template-OID
    $oid = Get-NextOid -Oid $lastOid
    
    $flags = $sourceTemplate.flags.Value
    $flags = $flags -bor [Pki.CATemplate.Flags]::IsModified -bxor [Pki.CATemplate.Flags]::IsDefault
    
    $newCertTemplate.put('flags', $flags)
    $newCertTemplate.put('displayName', $DisplayName)
    $newCertTemplate.put('revision', '100')
    $newCertTemplate.put('pKIDefaultKeySpec', $sourceTemplate.pKIDefaultKeySpec.Value)

    $newCertTemplate.put('pKIMaxIssuingDepth', $sourceTemplate.pKIMaxIssuingDepth.Value)
    $newCertTemplate.put('pKICriticalExtensions', $sourceTemplate.pKICriticalExtensions.Value)
    
    $eku = @($sourceTemplate.pKIExtendedKeyUsage.Value)
    $newCertTemplate.put('pKIExtendedKeyUsage', $eku)
    
    #$newCertTemplate.put('pKIDefaultCSPs','2,Microsoft Base Cryptographic Provider v1.0, 1,Microsoft Enhanced Cryptographic Provider v1.0')
    $newCertTemplate.put('msPKI-RA-Signature', '0')
    $newCertTemplate.put('msPKI-Enrollment-Flag', $EnrollmentFlags)
    $newCertTemplate.put('msPKI-Private-Key-Flag', $PrivateKeyFlags)
    $newCertTemplate.put('msPKI-Certificate-Name-Flag', $sourceTemplate.'msPKI-Certificate-Name-Flag'.Value)
    $newCertTemplate.put('msPKI-Minimal-Key-Size', $sourceTemplate.'msPKI-Minimal-Key-Size'.Value)
    
    if (-not $Version)
    {
        $Version = $sourceTemplate.'msPKI-Template-Schema-Version'.Value
    }
    $newCertTemplate.put('msPKI-Template-Schema-Version', $Version)
    $newCertTemplate.put('msPKI-Template-Minor-Revision', '1')
                   
    $newCertTemplate.put('msPKI-Cert-Template-OID', $oid)
    
    if (-not $ApplicationPolicy)
    {
        #V2 template
        $ap = $sourceTemplate.'msPKI-Certificate-Application-Policy'.Value
        if (-not $ap)
        {
            #V1 template
            $ap = $sourceTemplate.pKIExtendedKeyUsage.Value
        }
    }
    else
    {
        $ap = $ApplicationPolicy | ForEach-Object { $ApplicationPolicies[$_] }
    }
    
    if ($ap)
    {
        $newCertTemplate.put('msPKI-Certificate-Application-Policy', $ap)
    }
    
    $newCertTemplate.SetInfo()

    if ($KeyUsage)
    {
        $newCertTemplate.pKIKeyUsage = $KeyUsage
    }
    else
    {
        $newCertTemplate.pKIKeyUsage = $sourceTemplate.pKIKeyUsage
    }
    
    if ($ValidityPeriod)
    {
        $newCertTemplate.pKIExpirationPeriod.Value = [Pki.Period]::ToByteArray($ValidityPeriod)
    }
    else
    {
        $newCertTemplate.pKIExpirationPeriod = $sourceTemplate.pKIExpirationPeriod
    }
    
    if ($RenewalPeriod)
    {
        $newCertTemplate.pKIOverlapPeriod.Value = [Pki.Period]::ToByteArray($RenewalPeriod)
    }
    else
    {
        $newCertTemplate.pKIOverlapPeriod = $sourceTemplate.pKIOverlapPeriod
    }    
    $newCertTemplate.SetInfo()
}

function Get-NextOid
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Oid
    )
    
    $oidRange = $Oid.Substring(0, $Oid.LastIndexOf('.'))
    $lastNumber = $Oid.Substring($Oid.LastIndexOf('.') + 1)
    '{0}.{1}' -f $oidRange, ([int]$lastNumber + 1)
}

function Add-CATemplateStandardPermission
{
    [cmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TemplateName,
        
        [Parameter(Mandatory = $true)]
        [string[]]$SamAccountName
    )
    
    $configNc = ([adsi]'LDAP://RootDSE').configurationNamingContext
    $templateContainer = [adsi]"LDAP://CN=Certificate Templates,CN=Public Key Services,CN=Services,$configNc"
    Write-Verbose "Template container is '$templateContainer'"

    $template = $templateContainer.Children | Where-Object Name -eq $TemplateName
    if (-not $template)
    {
        Write-Error "The template '$TemplateName' could not be found"
        return
    }
   
    foreach ($name in $SamAccountName)
    {
        try
        {
            $sid = ([System.Security.Principal.NTAccount]$name).Translate([System.Security.Principal.SecurityIdentifier])
            $name = $sid.Translate([System.Security.Principal.NTAccount])

            dsacls $template.DistinguishedName /G "$($name):GR"
            dsacls $template.DistinguishedName /G "$($name):CA;Enroll"
            dsacls $template.DistinguishedName /G "$($name):CA;AutoEnrollment"
        }
        catch
        {
            Write-Error "The principal '$name' could not be found"
        }
    }
}

function Publish-CaTemplate
{
    [cmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TemplateName
    )
    
    $ca = Find-CertificateAuthority
    $caInfo = certutil.exe -CAInfo -Config $ca
    if ($caInfo -like '*No local Certification Authority*')
    {
        Write-Error 'No issuing CA found in the machines domain'
        return
    }
    $computerName = $ca.Split('\')[0]

    $start = Get-Date
    $done = $false
    $i = 0
    do
    {
        Write-Host "Trying to publish '$TemplateName' on '$ca' at ($(Get-Date)), retry count $i"
        certutil.exe -Config $ca -SetCAtemplates "+$TemplateName" | Out-Null
        if (-not $LASTEXITCODE)
        {
            $done = $true
        }
        else
        {
            if ($i % 5 -eq 0)
            {
                Get-Service -Name CertSvc -ComputerName $computerName | Restart-Service
            }

            $ex = New-Object System.ComponentModel.Win32Exception($LASTEXITCODE)
            Write-Host "Publishing the template '$TemplateName' failed: $($ex.Message)"

            Start-Sleep -Seconds 10
            $i++
        }
    }
    until ($done -or ((Get-Date) - $start).TotalMinutes -ge 10)
    Write-Host "Certificate templete '$TemplateName' published successfully"

    if ($LASTEXITCODE)
    {
        $ex = New-Object System.ComponentModel.Win32Exception($LASTEXITCODE)
        Write-Error -Message "Publishing the template '$TemplateName' failed: $($ex.Message)" -Exception $ex
        return
    }

    Write-Verbose "Successfully published template '$TemplateName'"
}

function Find-CertificateAuthority
{
    [cmdletBinding()]
    param(
        [string]$DomainName
    )

    Add-Type -AssemblyName System.DirectoryServices.AccountManagement

    try
    {
        $ctx = New-Object System.DirectoryServices.AccountManagement.PrincipalContext('Domain', $DomainName)
    }
    catch
    {
        Write-Error "The domain '$DomainName' could not be contacted"
        return
    }
    
    try
    {
        $configDn = ([ADSI]'LDAP://RootDSE').configurationNamingContext
        $cdpContainer = [ADSI]"LDAP://CN=CDP,CN=Public Key Services,CN=Services,$configDn"

        if (-not $cdpContainer)
        {
            Write-Error 'Could not connect to CDP container' -ErrorAction Stop
        }
    }
    catch
    {
        Write-Error "The domain '$DomainName' could not be contacted" -TargetObject $DomainName
        return
    }
                
    $caFound = $false
    foreach ($item in $cdpContainer.Children)
    {
        if (-not $caFound)
        {
            $machine = ($item.distinguishedName -split '=|,')[1]
            $caName = ($item.Children.distinguishedName -split '=|,')[1]

            if ($DomainName)
            {
                $group = [System.DirectoryServices.AccountManagement.GroupPrincipal]::FindByIdentity($ctx, 'Cert Publishers')
                $machine = $group.Members | Where-Object Name -eq $machine
                if ($machine.Context.Name -ne $DomainName)
                {
                    continue
                }
            }
                        
            $certificateAuthority = "$machine\$caName"
                        
            $result = certutil.exe -ping $certificateAuthority
            if ($result -match 'interface is alive*' )
            {
                $caFound = $true
            }
        }
    }
    
    if ($caFound)
    {
        $certificateAuthority
    }
    else
    {
        Write-Error "No Certificate Authority could be found in domain '$DomainName'"
    }
}

function Request-Certificate
{
    [cmdletBinding()]
    param (
        [Parameter(Mandatory = $true, HelpMessage = 'Please enter the subject beginning with CN=')]
        [ValidatePattern('CN=')]
        [string]$Subject,

        [Parameter(HelpMessage = 'Please enter the SAN domains as a comma separated list')]
        [string[]]$SAN,

        [Parameter(HelpMessage = 'Please enter the Online Certificate Authority')]
        [string]$OnlineCA,

        [Parameter(Mandatory = $true, HelpMessage = 'Please enter the Online Certificate Authority')]
        [string]$TemplateName
    )

    $infFile = [System.IO.Path]::GetTempFileName()
    $requestFile = [System.IO.Path]::GetTempFileName()
    $certFile = [System.IO.Path]::GetTempFileName()
    $rspFile = [System.IO.Path]::GetTempFileName()

    ### INI file generation
    $iniContent = @'
[Version]
Signature="$Windows NT$"
[NewRequest]
Subject="{0}"
Exportable=TRUE
KeyLength=2048
KeySpec=1
KeyUsage=0xA0
MachineKeySet=True
ProviderName="Microsoft RSA SChannel Cryptographic Provider"
ProviderType=12
SMIME=FALSE
RequestType=PKCS10
[Strings]
szOID_ENHANCED_KEY_USAGE = "2.5.29.37"
szOID_PKIX_KP_SERVER_AUTH = "1.3.6.1.5.5.7.3.1"
szOID_PKIX_KP_CLIENT_AUTH = "1.3.6.1.5.5.7.3.2"
'@

    $iniContent = $iniContent -f $Subject

    Add-Content -Path $infFile -Value $iniContent
    Write-Host "ini file created '$infFile'"
 
    if ($SAN)
    {
        Write-Host 'Adding SAN section'
        Add-Content -Path $infFile -Value 'szOID_SUBJECT_ALT_NAME2 = "2.5.29.17"'
        Add-Content -Path $infFile -Value '[Extensions]'
        Add-Content -Path $infFile -Value '2.5.29.17 = "{text}"'
 
        foreach ($s in $SAN)
        {
            Write-Host "`t $s"
            $temp = '_continue_ = "dns={0}&"' -f $s
            Add-Content -Path $infFile -Value $temp
        }
    }
 
    ### Certificate request generation
    Remove-Item -Path $requestFile
    Write-Host "Calling 'certreq.exe -new $infFile $requestFile | Out-Null'"
    certreq.exe -new $infFile $requestFile | Out-Null
 
    ### Online certificate request and import
    if (-not $OnlineCA)
    {
        Write-Host 'No CA given, trying to find one...'
        $OnlineCA = Find-CertificateAuthority -ErrorAction Stop
        Write-Host "Found CA '$OnlineCA'"
    }
    
    if (-not $OnlineCA)
    {
        Write-Host "No OnlineCA given and no one could be found in the machine's domain"
        return
    }
       
    Remove-Item -Path $certFile
    Write-Host "Calling 'certreq.exe -q -submit -attrib CertificateTemplate:$TemplateName -config $OnlineCA $requestFile $certFile | Out-Null'"
    certreq.exe -submit -q -attrib "CertificateTemplate:$TemplateName" -config $OnlineCA $requestFile $certFile | Out-Null

    if ($LASTEXITCODE)
    {
        $ex = New-Object System.ComponentModel.Win32Exception($LASTEXITCODE)
        Write-Host -Message "Submitting the certificate request failed: $($ex.Message)" -Exception $ex 
        return
    }
 
    Write-Host "Calling 'certreq.exe -accept $certFile'"
    certreq.exe -q -accept $certFile
    if ($LASTEXITCODE)
    {
        $ex = New-Object System.ComponentModel.Win32Exception($LASTEXITCODE)
        Write-Host -Message "Accepting the certificate failed: $($ex.Message)" -Exception $ex
        return
    }

    Copy-Item -Path $certFile -Destination c:\cert.cer -Force
    Copy-Item -Path $infFile -Destination c:\request.inf -Force

    $certPrint = [System.Security.Cryptography.X509Certificates.X509Certificate2][System.Security.Cryptography.X509Certificates.X509Certificate2]::CreateFromCertFile('C:\cert.cer')
    $certPrint

    Remove-Item -Path $infFile, $requestFile, $certFile, $rspFile, 'C:\cert.cer' -Force
}

$ExtendedKeyUsages = @{
    OldAuthorityKeyIdentifier = '.29.1'
    OldPrimaryKeyAttributes = '2.5.29.2'
    OldCertificatePolicies = '2.5.29.3'
    PrimaryKeyUsageRestriction = '2.5.29.4'
    SubjectDirectoryAttributes = '2.5.29.9'
    SubjectKeyIdentifier = '2.5.29.14'
    KeyUsage = '2.5.29.15'
    PrivateKeyUsagePeriod = '2.5.29.16'
    SubjectAlternativeName = '2.5.29.17'
    IssuerAlternativeName = '2.5.29.18'
    BasicConstraints = '2.5.29.19'
    CRLNumber = '2.5.29.20'
    Reasoncode = '2.5.29.21'
    HoldInstructionCode = '2.5.29.23'
    InvalidityDate = '2.5.29.24'
    DeltaCRLindicator = '2.5.29.27'
    IssuingDistributionPoint = '2.5.29.28'
    CertificateIssuer = '2.5.29.29'
    NameConstraints = '2.5.29.30'
    CRLDistributionPoints = '2.5.29.31'
    CertificatePolicies = '2.5.29.32'
    PolicyMappings = '2.5.29.33'
    AuthorityKeyIdentifier = '2.5.29.35'
    PolicyConstraints = '2.5.29.36'
    Extendedkeyusage = '2.5.29.37'
    FreshestCRL = '2.5.29.46'
    X509version3CertificateExtensionInhibitAny = '2.5.29.54'
}

#endregion Internals

#region Enable-AutoEnrollment
function Enable-AutoEnrollment {
    param
    (
        [switch]$Computer,
        [switch]$UserOrCodeSigning
    )
    
    Write-Host "Computer: '$Computer'"
    Write-Host "Computer: '$UserOrCodeSigning'"
    
    if ($Computer) {
        Write-Host 'Configuring for computer auto enrollment'
        [GPO.Helper]::SetGroupPolicy($true, 'Software\Policies\Microsoft\Cryptography\AutoEnrollment', 'AEPolicy', 7)
        [GPO.Helper]::SetGroupPolicy($true, 'Software\Policies\Microsoft\Cryptography\AutoEnrollment', 'OfflineExpirationPercent', 10)
        [GPO.Helper]::SetGroupPolicy($true, 'Software\Policies\Microsoft\Cryptography\AutoEnrollment', 'OfflineExpirationStoreNames', 'MY')
    }
    if ($UserOrCodeSigning) {
        Write-Host 'Configuring for user auto enrollment'
        [GPO.Helper]::SetGroupPolicy($false, 'Software\Policies\Microsoft\Cryptography\AutoEnrollment', 'AEPolicy', 7)
        [GPO.Helper]::SetGroupPolicy($false, 'Software\Policies\Microsoft\Cryptography\AutoEnrollment', 'OfflineExpirationPercent', 10)
        [GPO.Helper]::SetGroupPolicy($false, 'Software\Policies\Microsoft\Cryptography\AutoEnrollment', 'OfflineExpirationStoreNames', 'MY')
    }
    
    1..3 | ForEach-Object { gpupdate.exe /force; certutil.exe -pulse; Start-Sleep -Seconds 1 }
}
#endregion Enable-AutoEnrollment

#region Install-SoftwarePackage
function Install-SoftwarePackage
{
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        
        [string]$CommandLine,
        
        [bool]$AsScheduledJob,
        
        [bool]$UseShellExecute,

        [int[]]$ExpectedReturnCodes,

        [system.management.automation.pscredential]$Credential
    )    
    
    #region New-InstallProcess
    function New-InstallProcess
    {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Path,

            [string]$CommandLine,
            
            [bool]$UseShellExecute
        )
    
        $pInfo = New-Object -TypeName System.Diagnostics.ProcessStartInfo
        $pInfo.FileName = $Path
        
        $pInfo.UseShellExecute = $UseShellExecute
        if (-not $UseShellExecute)
        {
            $pInfo.RedirectStandardError = $true
            $pInfo.RedirectStandardOutput = $true
        }
        $pInfo.Arguments = $CommandLine

        $p = New-Object -TypeName System.Diagnostics.Process
        $p.StartInfo = $pInfo
        Write-Host "Starting process: $($pInfo.FileName) $($pInfo.Arguments)"
        $p.Start() | Out-Null
        Write-Host "The installation process ID is $($p.Id)"
        $p.WaitForExit()
        Write-Host 'Process exited. Reading output'

        $params = @{ Process = $p }
        if (-not $UseShellExecute)
        {
            $params.Add('Output', $p.StandardOutput.ReadToEnd())
            $params.Add('Error', $p.StandardError.ReadToEnd())
        }
        New-Object -TypeName PSObject -Property $params
    }
    #endregion New-InstallProcess

    if (-not (Test-Path -Path $Path -PathType Leaf))
    {
        Write-Host "The file '$Path' could not found"
        return        
    }
        
    $start = Get-Date
    Write-Host "Starting setup of '$Path' with the following command"
    Write-Host "`t$CommandLine"
    Write-Host "The timeout is some minutes, starting at '$start'"
    
    $installationMethod = [System.IO.Path]::GetExtension($Path)
    $installationFile = [System.IO.Path]::GetFileName($Path)
    
    if ($installationMethod -eq '.msi')
    {        
        [string]$CommandLine = if (-not $CommandLine)
        {
            @(
                "/I `"$Path`"", # Install this MSI
                '/QN', # Quietly, without a UI
                "/L*V `"$([System.IO.Path]::GetTempPath())$([System.IO.Path]::GetFileNameWithoutExtension($Path)).log`""     # Verbose output to this log
            )
        }
        else
        {
            '/I {0} {1}' -f $Path, $CommandLine # Install this MSI
        }
        
        Write-Host 'Installation arguments for MSI are:'
        Write-Host "`tPath: $Path"
        Write-Host "`tLog File: '`t$([System.IO.Path]::GetTempPath())$([System.IO.Path]::GetFileNameWithoutExtension($Path)).log'"
        
        $Path = 'msiexec.exe'
    }
    elseif ($installationMethod -eq '.msp')
    {
        [string]$CommandLine = if (-not $CommandLine)
        {
            @(
                "/P `"$Path`"", # Install this MSI
                '/QN', # Quietly, without a UI
                "/L*V `"$([System.IO.Path]::GetTempPath())$([System.IO.Path]::GetFileNameWithoutExtension($Path)).log`""     # Verbose output to this log
            )
        }
        else
        {
            '/P {0} {1}' -f $Path, $CommandLine # Install this MSI
        }
        
        Write-Host 'Installation arguments for MSI are:'
        Write-Host "`tPath: $Path"
        Write-Host "`tLog File: '`t$([System.IO.Path]::GetTempPath())$([System.IO.Path]::GetFileNameWithoutExtension($Path)).log'"
        
        $Path = 'msiexec.exe'
    }
    elseif ($installationMethod -eq '.msu')
    {        
        $tempRemoteFolder = [System.IO.Path]::GetTempFileName()
        Remove-Item -Path $tempRemoteFolder
        New-Item -ItemType Directory -Path $tempRemoteFolder
        expand.exe -F:* $Path $tempRemoteFolder
        $Path = 'dism.exe'
        $CommandLine = "/Online /Add-Package /PackagePath:""$tempRemoteFolder"" /NoRestart /Quiet"
    }
    elseif ($installationMethod -eq '.exe')
    { }
    else
    {
        Write-Host -Message 'The extension of the file to install is unknown'
        return
    }

    Write-Host "Starting installation of $installationMethod file"

    if ($AsScheduledJob)
    {
        $jobName = "InstallSWPack_$([guid]::NewGuid())"
        Write-Host "In the AsScheduledJob mode, creating scheduled job named '$jobName'"
            
        $scheduledJobParams = @{
            Name         = $jobName
            ScriptBlock  = (Get-Command -Name New-InstallProcess).ScriptBlock
            ArgumentList = $Path, $CommandLine, $UseShellExecute
            RunNow       = $true
        }
        if ($Credential) { $scheduledJobParams.Add('Credential', $Credential) }
        $scheduledJob = Register-ScheduledJob @scheduledJobParams
        Write-Host "ScheduledJob object registered with the ID $($scheduledJob.Id)"
        Start-Sleep -Seconds 5 #allow some time to let the scheduled task run
        
        while (-not $job)
        {
            Start-Sleep -Milliseconds 500
            $job = Get-Job -Name $jobName -ErrorAction SilentlyContinue
        }      
        $job | Wait-Job | Out-Null
        $result = $job | Receive-Job
    }
    else
    {
        $result = New-InstallProcess -Path $Path -CommandLine $CommandLine -UseShellExecute $UseShellExecute
    }
    
    Start-Sleep -Seconds 5
    
    if ($AsScheduledJob)
    {
        Write-Host "Unregistering scheduled job with ID $($scheduledJob.Id)"
        $scheduledJob | Unregister-ScheduledJob
    }

    if ($installationMethod -eq '.msu')
    {
        Remove-Item -Path $tempRemoteFolder -Recurse -Confirm:$false
    }
        
    Write-Host "Exit code of installation process is '$($result.Process.ExitCode)'"
    if ($null -ne $result.Process.ExitCode -and (0, 3010 + $ExpectedReturnCodes) -notcontains $result.Process.ExitCode)
    {
        throw $result.Process.ExitCode
    }
    else
    {
        Write-Host "Installation of '$installationFile' finished successfully"
        $result.Output
    }
}
#endregion Install-SoftwarePackage

try
{
    [Pki.Period]$temp = $null
}
catch
{
    Add-Type -TypeDefinition $pkiInternalsTypes
}

try
{
    [System.Security.Cryptography.X509Certificates.Win32]$temp = $null
}
catch
{
    Add-Type -TypeDefinition $certStoreTypes
}

try {
    [GPO.Helper]::GetGroupPolicy($true, 'SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentials', '1')
} catch {
    Add-Type -TypeDefinition $gpoType -IgnoreWarnings
}