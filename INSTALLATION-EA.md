# 🤖 Installation des EA MonWe (MT4 & MT5)

Connecte tes comptes MetaTrader à ton système Vercel via WebRequest.
Fonctionne sur **VPS** (recommandé) ou PC allumé.

---

## 🔄 Comment ça marche

```
Dashboard (tu valides) → Vercel (stocke le signal)
                              ↑
                         WebRequest toutes les 5s
                              ↑
                    EA sur MT4/MT5 (VPS) → exécute l'ordre
                              ↓
                    Confirme le ticket à Vercel
```

L'EA **interroge** Vercel régulièrement. Quand un signal validé arrive, il l'exécute et renvoie le numéro de ticket. Aucun logiciel intermédiaire.

---

## 📥 ÉTAPE 1 — Installer l'EA

### Pour MT5

1. Ouvre **MetaTrader 5** sur ton VPS
2. **Fichier → Ouvrir le dossier de données**
3. Va dans **MQL5 → Experts**
4. Copie `MonWe_WebRequest_MT5.mq5` dans ce dossier
5. Reviens dans MT5 → **Navigateur** → clic droit sur "Expert Advisors" → **Actualiser**

### Pour MT4

1. Ouvre **MetaTrader 4** sur ton VPS
2. **Fichier → Ouvrir le dossier de données**
3. Va dans **MQL4 → Experts**
4. Copie `MonWe_WebRequest_MT4.mq4` dans ce dossier
5. Reviens dans MT4 → **Navigateur** → clic droit sur "Expert Advisors" → **Actualiser**

---

## 🔓 ÉTAPE 2 — Autoriser l'URL (CRUCIAL)

Sans cette étape, l'EA ne pourra pas joindre Vercel (erreur 4060).

### MT5 et MT4 (identique)

1. **Outils → Options** (ou `Ctrl + O`)
2. Onglet **Expert Advisors**
3. Coche ✅ **"Autoriser WebRequest pour les URL listées"**
4. Dans la zone de texte, ajoute exactement :
   ```
   https://telegram-mt5-trader.vercel.app
   ```
5. Clique **OK**

---

## ⚙️ ÉTAPE 3 — Attacher l'EA au graphique

1. Ouvre un graphique (n'importe lequel, ex: XAUUSD)
2. Double-clique sur **MonWe_WebRequest_MT5** (ou MT4) dans le Navigateur
3. Dans la fenêtre de configuration, onglet **Paramètres d'entrée** :

| Paramètre | Valeur |
|-----------|--------|
| `InpApiUrl` | `https://telegram-mt5-trader.vercel.app` |
| `InpSecret` | **ton TELEGRAM_SECRET** (le même que dans Vercel) |
| `InpPollSeconds` | `5` (vérifie toutes les 5 secondes) |
| `InpMaxVolume` | `1.0` (sécurité — volume max par trade) |
| `InpMagic` | `20260626` |

4. Onglet **Communs** :
   - ✅ **Autoriser le trading algorithmique**
   - ✅ **Autoriser l'import de DLL** (pas obligatoire mais conseillé)
5. Clique **OK**

### Vérifier que ça tourne

En haut à droite du graphique : un **visage souriant 🙂** = EA actif.
Si tu vois un visage triste 🙁 → clique sur le bouton **"Algo Trading"** dans la barre d'outils.

---

## ✅ ÉTAPE 4 — Tester

1. Dans MT5/MT4 : onglet **Outils → Boîte à outils → Experts**
   Tu dois voir :
   ```
   === MonWe WebRequest EA démarré ===
   API: https://telegram-mt5-trader.vercel.app
   Polling: toutes les 5s
   ```

2. Depuis ton **dashboard**, valide et exécute un signal test

3. Dans les 5 secondes, l'EA doit afficher :
   ```
   📥 Signal: SELL XAUUSD @ 4024.5 (SL:4031 TP:4025 Vol:1.00)
   ✅ Exécuté: SELL XAUUSD — Ticket #123456
   ✓ Confirmation envoyée
   ```

4. Vérifie l'onglet **"Trade"** de MT5/MT4 → ta position est ouverte 🎉

---

## 🛡️ Sécurité & bonnes pratiques

✅ **InpMaxVolume** : limite le volume max par trade (protection)
✅ **Compte démo d'abord** : teste sur un compte démo avant le réel
✅ **VPS toujours allumé** : tes EA tournent 24/7
✅ **Un seul EA par compte** : n'attache pas l'EA sur 2 graphiques du même compte (double exécution)

---

## 🐛 Problèmes courants

### "WebRequest échoué. Code erreur: 4060"
→ L'URL n'est pas autorisée. Refais l'ÉTAPE 2.

### "Secret invalide"
→ `InpSecret` ne correspond pas au `TELEGRAM_SECRET` de Vercel. Vérifie qu'ils sont identiques.

### L'EA ne fait rien
→ Vérifie le visage 🙂 (EA actif) + bouton "Algo Trading" activé (vert).

### "Symbole introuvable"
→ Le symbole du signal (ex: XAUUSD) n'existe pas chez ton broker sous ce nom.
Certains brokers utilisent `GOLD`, `XAUUSD.m`, `XAUUSDm`, etc.
Dans ce cas, il faudra mapper les symboles (demande-moi).

### Ordre rejeté (code 10027 ou similaire)
→ "Algo Trading" désactivé côté terminal, ou marché fermé, ou marge insuffisante.

---

## 📊 Multi-comptes

Tu peux faire tourner l'EA sur **plusieurs comptes en même temps** :
- Ouvre plusieurs instances MT4/MT5 sur ton VPS (une par compte)
- Attache l'EA sur chacune avec le **même** `InpSecret`
- Chaque compte exécutera les mêmes signaux

⚠️ Note : avec le système actuel, chaque signal n'est pris qu'**une fois** (le premier EA qui le récupère le marque comme pris). Pour exécuter sur plusieurs comptes simultanément, demande-moi la version "multi-comptes" (un petit ajustement de l'endpoint).

---

## 🎯 Récapitulatif

```
□ EA copié dans MQL5/Experts (ou MQL4/Experts)
□ URL Vercel autorisée (Outils → Options → Expert Advisors)
□ EA attaché au graphique avec InpSecret correct
□ Visage 🙂 + Algo Trading activé
□ Test depuis le dashboard → ordre exécuté
```

---

**Besoin d'aide ?** Vérifie l'onglet **Experts** de MT4/MT5 — tous les messages de l'EA s'y affichent.
