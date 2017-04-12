---
layout: post
title:  "Sharing Secrets Protected by SSL Certificates"
date:   2017-04-12 +0100
categories: java
---
I will show how to share a secret with another server, based on SSL certificates. In our setup, a unique certificate is installed on each server. Say, server A has the secret and server B wants to access it.

To get the secret, B sends his certificate chain to A, A validates the certificate chain and compares the subject name with the list of allowed secret readers, which contains the name of B. As the actual certificate is not stored on A, the certificate can be renewed without any action on A. Then A encrypts the secret with the public key of B and sends it. This way A can be sure that only B can read it, as only B has the private key corresponding to the certificate. Finally B decrypts the secret using the private key.

For communication, we use a JAX-RS service:

``` java
public interface SecretService {
	@GET
	public String getSecret(List<String> certificateChain);
}
```
It is important to note that we not only send the certificate of B, but the whole certificate chain. This way, A can verify the certificate without obtaining any additional certificates.

Now, the code of B:
``` java
Encoder encoder = Base64.getEncoder().withoutPadding();
Decoder decoder = Base64.getDecoder();
SecretService secretService = ...;

// load key store
KeyStore ks = KeyStore.getInstance(KeyStore.getDefaultType());
ks.load(new FileInputStream(System.getProperty("javax.net.ssl.keyStore")), null);

// obtain and encode certificate chain
List<String> certificateChain = new ArrayList<>();
for (Certificate cert : ks.getCertificateChain("default")) {
    certificateChain.add(encoder.encodeToString(cert.getEncoded()));
}

// get encrypted key from server
byte[] encrypted = decoder.decode(secretService.getSecret(certificateChain));

// decrypt the secret
Key key = ks.getKey("default", "changeit".toCharArray());
Cipher cipher = Cipher.getInstance(key.getAlgorithm());
cipher.init(Cipher.DECRYPT_MODE, key);
String secret = cipher.doFinal(encrypted);
```

And finally the service implementation on A:

``` java
@Override
public String getSecret(List<String> certificateChain) {
	try {
		// load certificate path
		CertificateFactory cf = CertificateFactory.getInstance("X.509");
		List<X509Certificate> clientCerts = new ArrayList<>();
		for (String certificate: certificateChain) {
			 clientCerts.add((X509Certificate) cf
					 .generateCertificate(new ByteArrayInputStream(Base64.getDecoder().decode(certificate))));
		}

		// validate certification path
		TrustManagerFactory tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
		tmf.init((KeyStore) null);
		boolean trusted = false;
		for (TrustManager tm : tmf.getTrustManagers()) {
			 if (tm instanceof X509TrustManager) {
					 X509TrustManager trustManager = (X509TrustManager) tm;
					 HashSet<TrustAnchor> anchors = new HashSet<>();
					 for (X509Certificate cert : trustManager.getAcceptedIssuers()) {
							 anchors.add(new TrustAnchor(cert, null));
					 }
					 PKIXParameters params = new PKIXParameters(anchors);
					 params.setRevocationEnabled(false);
					 CertPath certPath = cf.generateCertPath(clientCerts);
					 CertPathValidator cpv = CertPathValidator.getInstance("PKIX");
					 cpv.validate(certPath, params);
					 trusted = true;
			 }
		}
		if (!trusted) {
			 throw new RuntimeException("Certificate chain is not trusted");
		}

		// determine if client/certificate is allowed to read the secret
		X509Certificate clientCert = clientCerts.get(0);
		Set<String> allowedSecretReaders=...;

		if (!allowedSecretReaders.contains(clientCert.getSubjectDN().getName())) {
			 throw new RuntimeException("client is not allowed to read signing key: " + clientCert.getSubjectDN());
		}

		// certificate is valid and client is allowed to read, return the secret
		String secret=...;
		Cipher cipher = Cipher.getInstance(clientCert.getPublicKey().getAlgorithm());
		cipher.init(Cipher.ENCRYPT_MODE, clientCert.getPublicKey());
		return Base64.getEncoder().withoutPadding()
			 .encodeToString(cipher.doFinal(secret));
	} catch (Exception e) {
 		throw new RuntimeException(e);
	}
}
```
