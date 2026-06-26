# 📋 MÉMO DE REPRISE — MonWe Trading (Telegram → MT5/MT4)

> Système semi-automatique : tu valides un signal dans le dashboard → il part sur
> Vercel → l'EA sur MT5/MT4 l'exécute sur ton compte Exness, puis reporte
> l'exécution et la fermeture automatiquement.

Dernière session : 26/06/2026 (nuit). Système complet et testé en réel (1 trade gagnant +186.12).

---

## 🔗 ACCÈS RAPIDES

| Quoi | Où |
|------|-----|
| Dashboard (app) | https://telegram-mt5-trader.vercel.app/dashboard.html |
| Santé du backend | https://telegram-mt5-trader.vercel.app/api/health |
| Code (GitHub) | https://github.com/Iyessiha/telegram-mt5-trader |
| Vercel projet | telegram-mt5-trader (équipe Yessiha's projects) |
| Supabase projet | "barax" — géré via l'intégration Vercel |

---

## ⚙️ CONFIGURATION (les 3 endroits du SECRET)

Le `TELEGRAM_SECRET` doit être **IDENTIQUE** à 3 endroits :

```
SECRET ACTUEL : monwe_mt5_2026_xK9pQ7
```

1. **Vercel** → Settings → Environment Variables → `TELEGRAM_SECRET`
2. **Dashboard** → onglet ⚙️ Paramètres → champ "Telegram Secret"
3. **EA (MT5/MT4)** → champ `TELEGRAM_SECRET` (⚠️ PAS le bot token !)

### Réglages EA (à remettre à chaque ré-installation)

| Paramètre | Valeur |
|-----------|--------|
| URL de base Vercel | `https://telegram-mt5-trader.vercel.app` |
| TELEGRAM_SECRET | `monwe_mt5_2026_xK9pQ7` |
| Fréquence (secondes) | `5` |
| Volume max | `1.0` (sécurité) |
| Suffixe symbole | `c` (Exness → XAUUSDc) |
| Préfixe symbole | (vide) |
| Symboles autorisés | `XAUUSD,BTCUSD` (Gold + BTC only) |
| Magic number | `20260626` |

---

## 🏦 COMPTE BROKER

- **Broker** : Exness (compte **Hedge**)
- **Compte testé** : Exness-MT5Real21 (⚠️ ARGENT RÉEL)
- **Symbole Gold** : `XAUUSDc` (avec le "c")
- **Conseil** : teste TOUJOURS sur un compte **DÉMO** avant le réel

---

## ✅ CE QUI EST FAIT (fonctionnel)

```
✅ Backend Vercel + Supabase (santé : tout OK)
✅ Dashboard de validation des signaux Station X
✅ Parsing TP corrigé (ne lit plus "1" dans "TP1")
✅ Multi-TP : si TP1/TP2/TP3 → ouvre 3 trades (1 par cible)
✅ EA MT5 + MT4 : exécution + confirmation du ticket
✅ Mapping symbole Exness (XAUUSD → XAUUSDc)
✅ Filtre Gold + BTC uniquement (rejette le reste)
✅ Multi-comptes / copy-trading (côté serveur prêt)
✅ Détection AUTO des fermetures → Performance synchronisée
✅ App mobile installable (PWA) + responsive
```

---

## 🔧 ÉTAPES RESTANTES (à la reprise)

### 1. Installer la DERNIÈRE version de l'EA ⭐ PRIORITÉ
La dernière version contient : suffixe `c` + filtre Gold/BTC + multi-compte + **détection auto des fermetures**.

- [ ] Copier `MonWe_WebRequest_MT5.mq5` dans `MQL5/Experts` (écraser l'ancien)
- [ ] MetaEditor → **Compiler (F7)**
- [ ] Retirer puis ré-attacher l'EA au graphique
- [ ] Vérifier les réglages (tableau ci-dessus), surtout le SECRET
- [ ] Onglet Communs → cocher **"Autoriser le trading algorithmique"**
- [ ] Vérifier le visage 🙂 + bouton "Algo Trading" vert

### 2. Tester sur compte DÉMO (bout-en-bout)
- [ ] Recharger le dashboard : `Ctrl+Shift+R` (cache)
- [ ] Coller un signal Station X → **Analyser**
- [ ] Vérifier que **Take Profit affiche la vraie valeur** (pas 1)
- [ ] Mettre un **petit volume** (0.01)
- [ ] EXÉCUTER → vérifier dans MT5 onglet Experts : `✅ Exécuté: SELL XAUUSDc`
- [ ] Fermer la position → vérifier que la **Performance se met à jour seule**

### 3. Sécurité (à faire absolument) 🔐
- [ ] **Régénérer le bot token Telegram** (@BotFather → `/revoke`) — il a été exposé
      puis le remettre dans Vercel (`TELEGRAM_BOT_TOKEN`)
- [ ] **Régénérer la clé Supabase** `sb_secret_...` (a été exposée dans le chat)
      puis la remettre dans Vercel (`SUPABASE_SERVICE_ROLE_KEY`)
- [ ] Optionnel : changer le `TELEGRAM_SECRET` (le remettre aux 3 endroits)

### 4. Multi-comptes (si tu veux brancher plusieurs comptes)
Le serveur est prêt (table `signal_executions`, filtrage par compte). Pour activer :
- [ ] Installer le même EA sur chaque compte (chacun envoie son numéro automatiquement)
- [ ] Même SECRET partout
- [ ] Chaque compte exécutera le même signal (copy-trading)

---

## 📲 INSTALLER L'APP SUR TÉLÉPHONE (PWA)

**iPhone (Safari obligatoire)** : ouvrir le dashboard → bouton Partager →
"Sur l'écran d'accueil" → Ajouter.

**Android (Chrome)** : une bannière "Installer" apparaît → cliquer Installer.

---

## 🐛 DÉPANNAGE RAPIDE

| Symptôme | Cause | Solution |
|----------|-------|----------|
| `Unauthorized` (dashboard ou EA) | Secret différent | Mettre le même secret partout (Reveal dans Vercel) |
| `Failed to fetch` | Mauvaise URL dans Paramètres | `https://telegram-mt5-trader.vercel.app` (sans slash final) |
| `Symbole introuvable: XAUUSD` | Ancien EA (sans suffixe) | Installer le nouvel EA, suffixe = `c` |
| Erreur 4060 dans Experts | URL non autorisée dans MT5 | Outils → Options → Expert Advisors → ajouter l'URL |
| Take Profit = 1 | Dashboard pas rechargé | `Ctrl+Shift+R` avant d'analyser |
| `MT5:undefined` dans les logs | Normal (test retiré du health) | Ignorer |
| Performance pas à jour | EA sans détection fermeture | Installer la dernière version de l'EA |

---

## 🔄 RAPPEL DU FLUX COMPLET

```
1. Signal Station X (copié à la main)
        ↓ (tu colles dans le dashboard)
2. Dashboard valide + analyse (Action, Entrée, SL, TP, R/R)
        ↓ (EXÉCUTER)
3. Vercel /api/telegram-webhook → stocke dans Supabase (status: executed)
        ↓ (EA interroge toutes les 5s)
4. EA /api/ea-poll → reçoit le signal → exécute sur XAUUSDc
        ↓
5. EA confirme le ticket → /api/ea-poll (POST)
        ↓ (quand la position se ferme : TP/SL/manuel)
6. EA détecte la fermeture → /api/ea-close → met à jour P&L + Performance
```

---

## 📂 FICHIERS CLÉS DU PROJET

- `public/dashboard.html` — l'app (validation, performance, alertes, PWA)
- `api/ea-poll.ts` — les EA récupèrent les signaux + confirment l'exécution
- `api/ea-close.ts` — les EA reportent les fermetures (auto-sync Performance)
- `api/pnl-stats.ts` — statistiques de performance
- `api/telegram-webhook.ts` — reçoit le signal validé du dashboard
- `MonWe_WebRequest_MT5.mq5` — EA pour MetaTrader 5
- `MonWe_WebRequest_MT4.mq4` — EA pour MetaTrader 4
- `INSTALLATION-EA.md` — guide d'installation détaillé des EA

---

*Tout le code est sur GitHub (Iyessiha/telegram-mt5-trader) et se déploie
automatiquement sur Vercel à chaque push. Bonne reprise ! 🚀*
