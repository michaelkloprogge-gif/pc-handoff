# Microsoft Store listing - PC Hand-off

Copy these into Partner Center. Screenshots: `store/screenshots/en` (English listing) and `store/screenshots/nl` (Dutch); the other languages use the English ones.

## Properties (all languages)

| Field | Value |
|---|---|
| Category | Utilities & tools |
| Privacy policy URL | https://github.com/michaelkloprogge-gif/pc-handoff#privacy |
| Website | https://github.com/michaelkloprogge-gif/pc-handoff |
| Support contact | https://github.com/michaelkloprogge-gif/pc-handoff/issues |
| Copyright | © 2026 Michael Kloprogge |
| Price | Free, all markets |
| System requirements | Windows 10 version 2004 or later, x64 |

## Notes for certification (Submission options)

Restricted capabilities - why they are needed:

- **runFullTrust**: PC Hand-off is a classic desktop app (Windows Forms). It only reads from the PC: personal folders, installed programs, browser profiles, the Windows licence, BitLocker state and hardware details (WMI, powercfg battery report).
- **allowElevation**: only when the user clicks "Run as administrator": then the app can also read how worn the drive is (storage reliability counters) for the spec sheet.

The app changes nothing on the PC. The Wipe page's "Start the reset" button opens Windows' own "Reset this PC" (systemreset.exe) after a confirmation; please don't press it on a test machine you want to keep.

Testing: no account needed. Start the app; the Check page fills in by itself. Updates come from the Store only (the app's own updater is switched off in the Store version).

---

## English (en-us)

**Description**

Selling, giving away or recycling your old Windows PC? PC Hand-off makes sure nothing of yours goes with it.

Check finds what the reset would wipe that may not be anywhere else yet: personal folders that are not in OneDrive or a PC Move backup, Outlook and Thunderbird mail, folders on a second drive, browser profiles that are not signed in. It also tells you if BitLocker is on (have your recovery key ready) and whether the Windows licence stays with the PC.

Sign out lists the licences and devices still tied to this PC, found from your installed programs - Microsoft 365, iTunes, Adobe, Steam, antivirus, WhatsApp and more - each with a button that opens the right page.

For the buyer writes the specs in plain words, ready for your ad: processor, memory, drive health, screen, battery health and Windows 11 support.

Wipe starts Windows' own "Reset this PC" and tells you exactly what to choose.

PC Hand-off only reads from your PC: nothing changes until you start the reset yourself. Free and open source (MIT licence), nothing uploaded.

**Product features**

- Finds files and mail that are only on this PC
- Lists licences and accounts to sign out of, from your installed programs
- A spec sheet for the buyer, including battery and drive health
- A guided Windows reset with every choice explained
- Only reads from your PC until you start the reset
- English, Dutch, German, French, Spanish, Italian and Polish; light and dark theme

**Keywords**: reset, sell PC, wipe, privacy, specs, deauthorize, recycle

---

## Nederlands (nl-nl)

**Beschrijving**

Je oude Windows-pc verkopen, weggeven of laten recyclen? PC Hand-off zorgt dat er niets van jou meegaat.

Controleren vindt wat de reset zou wissen en misschien nog nergens anders staat: persoonlijke mappen die niet in OneDrive of een PC Move-back-up staan, mail van Outlook en Thunderbird, mappen op een tweede schijf, browserprofielen waarin je niet bent ingelogd. Het zegt ook of BitLocker aan staat (houd je herstelsleutel bij de hand) en of de Windows-licentie bij de pc blijft.

Afmelden toont de licenties en apparaten die nog aan deze pc gekoppeld zijn, gevonden aan de hand van je programma's - Microsoft 365, iTunes, Adobe, Steam, antivirus, WhatsApp en meer - elk met een knop die de juiste pagina opent.

Voor de koper zet de specificaties in gewone taal op een rij, klaar voor je advertentie: processor, geheugen, gezondheid van de schijf, scherm, gezondheid van de accu en of Windows 11 erop kan.

Wissen start de eigen "Deze pc opnieuw instellen" van Windows en vertelt precies wat je moet kiezen.

PC Hand-off leest alleen van je pc: er verandert niets tot je zelf de reset start. Gratis en open source (MIT-licentie), er wordt niets geüpload.

**Productkenmerken**

- Vindt bestanden en mail die alleen op deze pc staan
- Toont licenties en accounts om af te melden, aan de hand van je programma's
- Een specificatieblad voor de koper, met de gezondheid van accu en schijf
- Een begeleide Windows-reset waarbij elke keuze wordt uitgelegd
- Leest alleen van je pc tot je de reset start
- Nederlands, Engels, Duits, Frans, Spaans, Italiaans en Pools; licht en donker thema

**Trefwoorden**: reset, pc verkopen, wissen, privacy, specificaties, afmelden, recyclen

---

## Deutsch (de-de)

**Beschreibung**

Du willst deinen alten Windows-PC verkaufen, verschenken oder recyceln? PC Hand-off sorgt dafür, dass nichts von dir mitgeht.

Prüfen findet, was das Zurücksetzen löschen würde und vielleicht noch nirgends sonst ist: persönliche Ordner, die nicht in OneDrive oder einer PC-Move-Sicherung sind, Mails aus Outlook und Thunderbird, Ordner auf einem zweiten Laufwerk, Browserprofile ohne Anmeldung. Es sagt dir auch, ob BitLocker an ist (halte deinen Wiederherstellungsschlüssel bereit) und ob die Windows-Lizenz beim PC bleibt.

Abmelden zeigt die Lizenzen und Geräte, die noch an diesen PC gebunden sind, gefunden anhand deiner Programme - Microsoft 365, iTunes, Adobe, Steam, Virenschutz, WhatsApp und mehr - jeweils mit einer Schaltfläche, die die richtige Seite öffnet.

Für den Käufer schreibt die technischen Daten in einfachen Worten auf, fertig für deine Anzeige: Prozessor, Arbeitsspeicher, Zustand des Laufwerks, Bildschirm, Zustand des Akkus und ob Windows 11 läuft.

Löschen startet das eigene "Diesen PC zurücksetzen" von Windows und sagt dir genau, was du wählen sollst.

PC Hand-off liest nur von deinem PC: Nichts ändert sich, bis du das Zurücksetzen selbst startest. Kostenlos und Open Source (MIT-Lizenz), nichts wird hochgeladen.

**Produktfeatures**

- Findet Dateien und Mails, die nur auf diesem PC sind
- Zeigt Lizenzen und Konten zum Abmelden, anhand deiner Programme
- Ein Datenblatt für den Käufer, mit Zustand von Akku und Laufwerk
- Ein geführtes Zurücksetzen von Windows, jede Auswahl erklärt
- Liest nur von deinem PC, bis du das Zurücksetzen startest
- Deutsch, Englisch, Niederländisch, Französisch, Spanisch, Italienisch und Polnisch; helles und dunkles Design

**Suchbegriffe**: zurücksetzen, PC verkaufen, löschen, Datenschutz, Datenblatt, abmelden, recyceln

---

## Français (fr-fr)

**Description**

Tu vends, donnes ou recycles ton ancien PC Windows ? PC Hand-off veille à ce que rien de toi ne parte avec lui.

Vérifier trouve ce que la réinitialisation effacerait et qui n'est peut-être encore nulle part ailleurs : dossiers personnels absents de OneDrive ou d'une sauvegarde PC Move, mails d'Outlook et de Thunderbird, dossiers sur un second disque, profils de navigateur sans compte connecté. Il te dit aussi si BitLocker est activé (garde ta clé de récupération à portée de main) et si la licence Windows reste avec le PC.

Déconnexion liste les licences et appareils encore liés à ce PC, trouvés d'après tes programmes installés - Microsoft 365, iTunes, Adobe, Steam, antivirus, WhatsApp et d'autres - chacun avec un bouton qui ouvre la bonne page.

Pour l'acheteur rédige les caractéristiques en mots simples, prêtes pour ton annonce : processeur, mémoire, état du disque, écran, état de la batterie et compatibilité Windows 11.

Effacer lance la fonction « Réinitialiser ce PC » de Windows et te dit exactement quoi choisir.

PC Hand-off ne fait que lire ton PC : rien ne change tant que tu ne lances pas toi-même la réinitialisation. Gratuit et open source (licence MIT), rien n'est envoyé en ligne.

**Fonctionnalités**

- Trouve les fichiers et mails qui ne sont que sur ce PC
- Liste les licences et comptes à déconnecter, d'après tes programmes installés
- Une fiche technique pour l'acheteur, avec l'état de la batterie et du disque
- Une réinitialisation de Windows guidée, chaque choix expliqué
- Ne fait que lire ton PC jusqu'à ce que tu lances la réinitialisation
- Français, anglais, néerlandais, allemand, espagnol, italien et polonais ; thème clair et sombre

**Mots-clés** : réinitialiser, vendre PC, effacer, confidentialité, caractéristiques, déconnecter, recycler

---

## Español (es-es)

**Descripción**

¿Vas a vender, regalar o reciclar tu PC antiguo con Windows? PC Hand-off se asegura de que no se vaya nada tuyo con él.

Comprobar encuentra lo que el restablecimiento borraría y quizá todavía no está en ningún otro sitio: carpetas personales que no están en OneDrive ni en una copia de PC Move, correo de Outlook y Thunderbird, carpetas en un segundo disco, perfiles del navegador sin sesión iniciada. También te dice si BitLocker está activado (ten a mano tu clave de recuperación) y si la licencia de Windows se queda con el PC.

Cerrar sesión muestra las licencias y dispositivos que siguen vinculados a este PC, encontrados a partir de tus programas instalados - Microsoft 365, iTunes, Adobe, Steam, antivirus, WhatsApp y más - cada uno con un botón que abre la página correcta.

Para el comprador escribe las características en palabras sencillas, listas para tu anuncio: procesador, memoria, estado del disco, pantalla, estado de la batería y compatibilidad con Windows 11.

Borrar inicia el propio «Restablecer este PC» de Windows y te dice exactamente qué elegir.

PC Hand-off solo lee de tu PC: nada cambia hasta que tú mismo inicies el restablecimiento. Gratuito y de código abierto (licencia MIT), no se sube nada.

**Características**

- Encuentra archivos y correo que solo están en este PC
- Muestra licencias y cuentas de las que cerrar sesión, a partir de tus programas instalados
- Una ficha técnica para el comprador, con el estado de la batería y del disco
- Un restablecimiento de Windows guiado, con cada opción explicada
- Solo lee de tu PC hasta que inicias el restablecimiento
- Español, inglés, neerlandés, alemán, francés, italiano y polaco; tema claro y oscuro

**Palabras clave**: restablecer, vender PC, borrar, privacidad, características, cerrar sesión, reciclar

---

## Italiano (it-it)

**Descrizione**

Vendi, regali o ricicli il tuo vecchio PC Windows? PC Hand-off si assicura che non se ne vada nulla di tuo.

Controlla trova ciò che il ripristino cancellerebbe e che forse non è ancora da nessun'altra parte: cartelle personali che non sono in OneDrive o in un backup di PC Move, posta di Outlook e Thunderbird, cartelle su un secondo disco, profili del browser senza accesso. Ti dice anche se BitLocker è attivo (tieni a portata di mano la chiave di ripristino) e se la licenza di Windows resta con il PC.

Disconnetti elenca le licenze e i dispositivi ancora legati a questo PC, trovati in base ai programmi installati - Microsoft 365, iTunes, Adobe, Steam, antivirus, WhatsApp e altri - ognuno con un pulsante che apre la pagina giusta.

Per l'acquirente scrive le caratteristiche in parole semplici, pronte per il tuo annuncio: processore, memoria, stato del disco, schermo, stato della batteria e compatibilità con Windows 11.

Cancella avvia la funzione "Reimposta il PC" di Windows e ti dice esattamente cosa scegliere.

PC Hand-off legge soltanto dal tuo PC: nulla cambia finché non avvii tu il ripristino. Gratuito e open source (licenza MIT), nulla viene caricato online.

**Funzionalità**

- Trova file e posta che sono solo su questo PC
- Elenca licenze e account da disconnettere, in base ai programmi installati
- Una scheda tecnica per l'acquirente, con lo stato di batteria e disco
- Un ripristino di Windows guidato, con ogni scelta spiegata
- Legge soltanto dal tuo PC finché non avvii il ripristino
- Italiano, inglese, olandese, tedesco, francese, spagnolo e polacco; tema chiaro e scuro

**Parole chiave**: ripristino, vendere PC, cancellare, privacy, caratteristiche, disconnettere, riciclare

---

## Polski (pl-pl)

**Opis**

Sprzedajesz, oddajesz albo oddajesz do recyklingu stary komputer z Windows? PC Hand-off dba o to, żeby nic Twojego z nim nie odeszło.

Sprawdź znajduje to, co reset by usunął, a czego może jeszcze nie ma nigdzie indziej: foldery osobiste spoza OneDrive i kopii PC Move, pocztę z Outlooka i Thunderbirda, foldery na drugim dysku, profile przeglądarki bez zalogowanego konta. Mówi też, czy BitLocker jest włączony (miej pod ręką klucz odzyskiwania) i czy licencja Windows zostaje z komputerem.

Wyloguj pokazuje licencje i urządzenia wciąż powiązane z tym komputerem, znalezione na podstawie zainstalowanych programów - Microsoft 365, iTunes, Adobe, Steam, antywirus, WhatsApp i inne - każde z przyciskiem otwierającym właściwą stronę.

Dla kupującego opisuje parametry prostymi słowami, gotowe do ogłoszenia: procesor, pamięć, stan dysku, ekran, stan baterii i obsługę Windows 11.

Wyczyść uruchamia wbudowane w Windows "Resetuj ten komputer" i mówi dokładnie, co wybrać.

PC Hand-off tylko czyta z Twojego komputera: nic się nie zmienia, dopóki sam nie uruchomisz resetu. Bezpłatny i open source (licencja MIT), nic nie jest wysyłane do sieci.

**Funkcje**

- Znajduje pliki i pocztę, które są tylko na tym komputerze
- Pokazuje licencje i konta do wylogowania, na podstawie zainstalowanych programów
- Karta parametrów dla kupującego, ze stanem baterii i dysku
- Prowadzony reset Windows z wyjaśnieniem każdego wyboru
- Tylko czyta z komputera, dopóki nie uruchomisz resetu
- Polski, angielski, niderlandzki, niemiecki, francuski, hiszpański i włoski; jasny i ciemny motyw

**Słowa kluczowe**: reset, sprzedaż komputera, czyszczenie, prywatność, parametry, wylogowanie, recykling
