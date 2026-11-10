package com.hiroki.hermesdeck

import android.app.Activity
import android.app.AlertDialog
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.provider.OpenableColumns
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class MainActivity : Activity() {

    companion object {
        private const val DECKCTL = "sh /data/adb/hermes_deck/deckctl.sh"
        private const val REQ_UPLOAD = 4711
        private const val BG = 0xFF0F1115.toInt()
        private const val CARD = 0xFF171A21.toInt()
        private const val BORDER = 0xFF2A2F3A.toInt()
        private const val ACCENT = 0xFF7C6FF0.toInt()
        private const val TXT = 0xFFF2F3F7.toInt()
        private const val SUB = 0xFF9AA3B2.toInt()
        private const val GREEN = 0xFF3ECF8E.toInt()
        private const val RED = 0xFFFF6B6B.toInt()
        private const val AMBER = 0xFFFFC24B.toInt()
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val pool = Executors.newCachedThreadPool()

    private lateinit var contentFrame: FrameLayout
    private val pages = mutableListOf<View>()
    private val navButtons = mutableListOf<TextView>()
    private var currentTab = 0

    // Beranda
    private lateinit var btnModeBiasa: Button
    private lateinit var btnModeAi: Button
    private lateinit var tvModeNow: TextView
    private lateinit var tvGateway: TextView
    private lateinit var tvRouter: TextView
    private lateinit var tvWebui: TextView
    private lateinit var tvTailscale: TextView
    private lateinit var tvPhantom: TextView
    private lateinit var tvHomeInfo: TextView
    private lateinit var btnHelperOn: Button
    private lateinit var btnHelperOff: Button
    private lateinit var tvHelperNow: TextView
    private lateinit var tvSshd: TextView
    private var currentMode = ""
    private var currentHelper = ""
    private var modeBusy = false
    private var helperBusy = false
    private var statusBusy = false

    // WebView
    private var hermesWeb: WebView? = null
    private var routerWeb: WebView? = null

    // Konsol
    private lateinit var consoleScroll: ScrollView
    private lateinit var consoleOut: LinearLayout
    private lateinit var consoleInput: EditText

    // Berkas
    private var currentPath = "."
    private var clipboardRel: String? = null
    private lateinit var btnPaste: Button
    private lateinit var tvClipInfo: TextView
    private var currentFileContent = ""
    private lateinit var tvPath: TextView
    private lateinit var fileList: LinearLayout
    private lateinit var tvFileTitle: TextView
    private lateinit var tvFileContent: TextView
    private lateinit var fileScroll: ScrollView

    // ===== Util =====

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    private fun shellQuote(s: String): String = "'" + s.replace("'", "'\\''") + "'"

    private fun toast(s: String) = Toast.makeText(this, s, Toast.LENGTH_SHORT).show()

    /** Jalankan deckctl lewat su -c di thread latar; callback dipanggil di UI thread. */
    private fun runDeck(args: String, timeoutSec: Long = 45, cb: (String) -> Unit) {
        pool.execute {
            val out = try {
                val pb = ProcessBuilder("su", "-c", "$DECKCTL $args")
                pb.redirectErrorStream(true)
                val p = pb.start()
                val text = p.inputStream.bufferedReader().readText()
                if (!p.waitFor(timeoutSec, TimeUnit.SECONDS)) {
                    p.destroyForcibly()
                    (text + "\n[timeout ${timeoutSec} dtk]").trim()
                } else text.trim()
            } catch (e: Exception) {
                "ERROR: ${e.message}"
            }
            mainHandler.post { cb(out) }
        }
    }

    // ===== Komponen UI =====

    private fun tv(s: String, size: Float = 14f, color: Int = TXT, bold: Boolean = false, mono: Boolean = false): TextView {
        val t = TextView(this)
        t.text = s
        t.textSize = size
        t.setTextColor(color)
        if (mono) t.typeface = Typeface.MONOSPACE
        else if (bold) t.setTypeface(null, Typeface.BOLD)
        return t
    }

    private fun card(): LinearLayout {
        val l = LinearLayout(this)
        l.orientation = LinearLayout.VERTICAL
        l.setPadding(dp(14), dp(12), dp(14), dp(12))
        l.background = GradientDrawable().apply {
            cornerRadius = dp(12).toFloat()
            setColor(CARD)
            setStroke(dp(1), BORDER)
        }
        val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        lp.setMargins(0, 0, 0, dp(12))
        l.layoutParams = lp
        return l
    }

    private fun accentButton(s: String): Button {
        val b = Button(this)
        b.text = s
        b.setTextColor(0xFFFFFFFF.toInt())
        b.textSize = 14f
        b.setTypeface(null, Typeface.BOLD)
        b.isAllCaps = false
        b.background = GradientDrawable().apply {
            cornerRadius = dp(10).toFloat()
            setColor(ACCENT)
        }
        b.setPadding(dp(14), dp(10), dp(14), dp(10))
        return b
    }

    private fun ghostButton(s: String): Button {
        val b = Button(this)
        b.text = s
        b.setTextColor(TXT)
        b.textSize = 14f
        b.isAllCaps = false
        b.background = GradientDrawable().apply {
            cornerRadius = dp(10).toFloat()
            setColor(CARD)
            setStroke(dp(1), BORDER)
        }
        b.setPadding(dp(14), dp(10), dp(14), dp(10))
        return b
    }

    private fun pageScroll(content: LinearLayout): ScrollView {
        val sv = ScrollView(this)
        sv.setBackgroundColor(BG)
        content.setPadding(dp(16), dp(14), dp(16), dp(20))
        sv.addView(content, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        return sv
    }

    private fun lpWrap(marginTop: Int = 0): LinearLayout.LayoutParams {
        val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        if (marginTop > 0) lp.topMargin = dp(marginTop)
        return lp
    }

    private fun lpWeight(): LinearLayout.LayoutParams =
        LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)

    // ===== onCreate / navigasi =====

    override fun onCreate(b: Bundle?) {
        super.onCreate(b)
        val root = LinearLayout(this)
        root.orientation = LinearLayout.VERTICAL
        root.setBackgroundColor(BG)

        val header = LinearLayout(this)
        header.orientation = LinearLayout.VERTICAL
        header.setPadding(dp(16), dp(14), dp(16), dp(10))
        header.addView(tv("Hermes Deck", 20f, TXT, bold = true))
        header.addView(tv("Panel kendali stack Hermes lokal · v1.3", 12f, SUB))
        root.addView(header)

        contentFrame = FrameLayout(this)
        root.addView(contentFrame, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))

        val divider = View(this)
        divider.setBackgroundColor(BORDER)
        root.addView(divider, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(1)))

        val nav = LinearLayout(this)
        nav.orientation = LinearLayout.HORIZONTAL
        nav.setBackgroundColor(CARD)
        nav.setPadding(dp(4), dp(6), dp(4), dp(6))
        val labels = listOf("Beranda", "Hermes", "Konsol", "Router", "Berkas")
        labels.forEachIndexed { i, label ->
            val nb = tv(label, 12f, SUB, bold = true)
            nb.gravity = Gravity.CENTER
            nb.setPadding(dp(2), dp(10), dp(2), dp(10))
            nb.setOnClickListener { showTab(i) }
            navButtons.add(nb)
            nav.addView(nb, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        }
        root.addView(nav)

        pages.add(buildHomePage())
        pages.add(buildWebPage("http://127.0.0.1:8787", "hermes-webui · 127.0.0.1:8787") { hermesWeb = it })
        pages.add(buildConsolePage())
        pages.add(buildWebPage("http://127.0.0.1:20128", "dashboard 9router · 127.0.0.1:20128") { routerWeb = it })
        pages.add(buildFilesPage())
        pages.forEach { contentFrame.addView(it, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)) }

        setContentView(root)
        showTab(0)
        refreshStatus()
        loadDir(".")
    }

    private fun showTab(i: Int) {
        currentTab = i
        pages.forEachIndexed { idx, v -> v.visibility = if (idx == i) View.VISIBLE else View.GONE }
        navButtons.forEachIndexed { idx, nb ->
            if (idx == i) {
                nb.setTextColor(0xFFFFFFFF.toInt())
                nb.background = GradientDrawable().apply {
                    cornerRadius = dp(8).toFloat()
                    setColor(ACCENT)
                }
            } else {
                nb.setTextColor(SUB)
                nb.background = null
            }
        }
    }

    // ===== Tab 1: Beranda =====

    private fun statusRow(parent: LinearLayout, label: String): TextView {
        val row = LinearLayout(this)
        row.orientation = LinearLayout.HORIZONTAL
        row.setPadding(0, dp(5), 0, dp(5))
        val l = tv(label, 13f, SUB)
        row.addView(l, lpWeight())
        val v = tv("…", 13f, TXT, bold = true)
        v.gravity = Gravity.END
        row.addView(v, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        parent.addView(row)
        return v
    }

    private fun buildHomePage(): View {
        val col = LinearLayout(this)
        col.orientation = LinearLayout.VERTICAL

        // Kartu mode
        val modeCard = card()
        modeCard.addView(tv("Mode HP", 15f, TXT, bold = true))
        tvModeNow = tv("Mode saat ini: …", 12f, SUB)
        modeCard.addView(tvModeNow)
        val modeRow = LinearLayout(this)
        modeRow.orientation = LinearLayout.HORIZONTAL
        modeRow.setPadding(0, dp(10), 0, 0)
        btnModeBiasa = ghostButton("HP Biasa")
        btnModeAi = ghostButton("Mode AI")
        btnModeBiasa.textSize = 16f
        btnModeAi.textSize = 16f
        val lpB = lpWeight(); lpB.marginEnd = dp(6)
        val lpA = lpWeight(); lpA.marginStart = dp(6)
        modeRow.addView(btnModeBiasa, lpB)
        modeRow.addView(btnModeAi, lpA)
        modeCard.addView(modeRow)
        btnModeBiasa.setOnClickListener { setMode("biasa") }
        btnModeAi.setOnClickListener { setMode("ai") }
        col.addView(modeCard)

        // Kartu status
        val stCard = card()
        val headRow = LinearLayout(this)
        headRow.orientation = LinearLayout.HORIZONTAL
        val title = tv("Status Stack", 15f, TXT, bold = true)
        headRow.addView(title, lpWeight())
        val btnRefresh = ghostButton("Refresh")
        btnRefresh.textSize = 12f
        btnRefresh.setOnClickListener { refreshStatus() }
        headRow.addView(btnRefresh, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        stCard.addView(headRow)
        tvGateway = statusRow(stCard, "Gateway")
        tvRouter = statusRow(stCard, "Router (model)")
        tvWebui = statusRow(stCard, "WebUI")
        tvTailscale = statusRow(stCard, "Tailscale")
        tvSshd = statusRow(stCard, "SSH (agen pembantu)")
        tvPhantom = statusRow(stCard, "Phantom limit")
        col.addView(stCard)

        // Kartu Agen Pembantu (akses jarak jauh)
        val hpCard = card()
        hpCard.addView(tv("Agen Pembantu", 15f, TXT, bold = true))
        tvHelperNow = tv("Status: …", 12f, SUB)
        hpCard.addView(tvHelperNow)
        hpCard.addView(
            tv("Menghidupkan Tailscale + SSH supaya asisten bisa masuk dari jauh. Default mati — nyalakan hanya saat dibutuhkan.", 11f, SUB),
            lpWrap(4)
        )
        val hpRow = LinearLayout(this)
        hpRow.orientation = LinearLayout.HORIZONTAL
        hpRow.setPadding(0, dp(10), 0, 0)
        btnHelperOff = ghostButton("Matikan")
        btnHelperOn = ghostButton("Hidupkan")
        btnHelperOff.textSize = 14f
        btnHelperOn.textSize = 14f
        val lpHB = lpWeight(); lpHB.marginEnd = dp(6)
        val lpHA = lpWeight(); lpHA.marginStart = dp(6)
        hpRow.addView(btnHelperOff, lpHB)
        hpRow.addView(btnHelperOn, lpHA)
        hpCard.addView(hpRow)
        btnHelperOff.setOnClickListener { setHelper(false) }
        btnHelperOn.setOnClickListener { setHelper(true) }
        col.addView(hpCard)

        // Aksi cepat
        val actCard = card()
        actCard.addView(tv("Aksi Cepat", 15f, TXT, bold = true))
        val actRow = LinearLayout(this)
        actRow.orientation = LinearLayout.HORIZONTAL
        actRow.setPadding(0, dp(10), 0, 0)
        val btnRestart = accentButton("Restart Stack")
        btnRestart.setOnClickListener { doRestart() }
        val lpR = lpWeight(); lpR.marginEnd = dp(6)
        actRow.addView(btnRestart, lpR)
        val btnLog = ghostButton("Lihat Log")
        btnLog.setOnClickListener { showLog() }
        val lpL = lpWeight(); lpL.marginStart = dp(6)
        actRow.addView(btnLog, lpL)
        actCard.addView(actRow)
        tvHomeInfo = tv("", 12f, SUB)
        actCard.addView(tvHomeInfo, lpWrap(8))
        col.addView(actCard)

        return pageScroll(col)
    }

    private fun paintModeButtons() {
        fun style(b: Button, active: Boolean) {
            if (active) {
                b.setTextColor(0xFFFFFFFF.toInt())
                b.background = GradientDrawable().apply {
                    cornerRadius = dp(10).toFloat()
                    setColor(ACCENT)
                }
            } else {
                b.setTextColor(TXT)
                b.background = GradientDrawable().apply {
                    cornerRadius = dp(10).toFloat()
                    setColor(CARD)
                    setStroke(dp(1), BORDER)
                }
            }
        }
        style(btnModeAi, currentMode == "ai")
        style(btnModeBiasa, currentMode == "biasa")
        tvModeNow.text = when (currentMode) {
            "ai" -> "Mode saat ini: Mode AI"
            "biasa" -> "Mode saat ini: HP Biasa"
            else -> "Mode saat ini: …"
        }
    }

    private fun setMode(m: String) {
        // Debounce v1.1: satu perintah mode pada satu waktu. Di v1.0 tombol
        // tetap aktif selama perintah berjalan; ketukan berulang menulis
        // mode berkali-kali dan membuat dua pengendali bertarung.
        if (modeBusy) return
        if (m == currentMode) {
            toast(if (m == "ai") "Sudah di Mode AI" else "Sudah di HP Biasa")
            return
        }
        modeBusy = true
        btnModeAi.isEnabled = false
        btnModeBiasa.isEnabled = false
        btnModeAi.alpha = 0.5f
        btnModeBiasa.alpha = 0.5f
        tvHomeInfo.text = "Menerapkan mode $m…"
        runDeck("mode $m", 120) { out ->
            modeBusy = false
            btnModeAi.isEnabled = true
            btnModeBiasa.isEnabled = true
            btnModeAi.alpha = 1f
            btnModeBiasa.alpha = 1f
            tvHomeInfo.text = out.ifEmpty { "Mode $m diterapkan." }
            currentMode = m
            paintModeButtons()
            refreshStatus()
        }
    }

    private fun paintHelperButtons() {
        fun style(b: Button, active: Boolean) {
            if (active) {
                b.setTextColor(0xFFFFFFFF.toInt())
                b.background = GradientDrawable().apply {
                    cornerRadius = dp(10).toFloat()
                    setColor(ACCENT)
                }
            } else {
                b.setTextColor(TXT)
                b.background = GradientDrawable().apply {
                    cornerRadius = dp(10).toFloat()
                    setColor(CARD)
                    setStroke(dp(1), BORDER)
                }
            }
        }
        if (!::btnHelperOn.isInitialized) return
        style(btnHelperOn, currentHelper == "on")
        style(btnHelperOff, currentHelper == "off")
        tvHelperNow.text = when (currentHelper) {
            "on" -> "Status: AKTIF — Tailscale + SSH menyala"
            "off" -> "Status: mati (default)"
            else -> "Status: …"
        }
    }

    private fun setHelper(on: Boolean) {
        if (helperBusy) return
        val target = if (on) "on" else "off"
        if (target == currentHelper) {
            toast(if (on) "Agen pembantu sudah aktif" else "Agen pembantu sudah mati")
            return
        }
        helperBusy = true
        btnHelperOn.isEnabled = false
        btnHelperOff.isEnabled = false
        btnHelperOn.alpha = 0.5f
        btnHelperOff.alpha = 0.5f
        tvHomeInfo.text = if (on) "Menghidupkan agen pembantu…" else "Mematikan agen pembantu…"
        runDeck("helper $target", 60) { out ->
            helperBusy = false
            btnHelperOn.isEnabled = true
            btnHelperOff.isEnabled = true
            btnHelperOn.alpha = 1f
            btnHelperOff.alpha = 1f
            tvHomeInfo.text = out.ifEmpty { "Agen pembantu: $target." }
            currentHelper = target
            paintHelperButtons()
            if (on) toast("Tailscale dibuka — pastikan tampil Connected, lalu kembali ke Deck")
            refreshStatus()
        }
    }

    private fun upText(v: String): Pair<String, Int> = when (v.lowercase()) {
        "up" -> "UP" to GREEN
        "down" -> "DOWN" to RED
        else -> v to TXT
    }

    private fun refreshStatus() {
        if (statusBusy) return
        statusBusy = true
        runDeck("status", 90) { out ->
            statusBusy = false
            if (out.startsWith("ERROR")) {
                tvHomeInfo.text = out
                return@runDeck
            }
            val map = mutableMapOf<String, String>()
            out.lines().forEach { line ->
                val idx = line.indexOf('=')
                if (idx > 0) map[line.substring(0, idx).trim()] = line.substring(idx + 1).trim()
            }
            currentMode = map["mode"] ?: currentMode
            paintModeButtons()
            currentHelper = map["helper"] ?: currentHelper
            paintHelperButtons()
            fun setUp(target: TextView, key: String) {
                val (txt, col) = upText(map[key] ?: "?")
                target.text = txt
                target.setTextColor(col)
            }
            setUp(tvGateway, "gateway")
            setUp(tvWebui, "webui")
            setUp(tvTailscale, "tailscale")
            setUp(tvSshd, "sshd")
            val (rTxt, rCol) = upText(map["router"] ?: "?")
            val models = map["models"] ?: "?"
            tvRouter.text = "$rTxt · $models model"
            tvRouter.setTextColor(rCol)
            tvPhantom.text = map["phantom"] ?: "?"
            tvPhantom.setTextColor(TXT)
        }
    }

    private fun doRestart() {
        tvHomeInfo.text = "Memulai ulang stack…"
        runDeck("restart", 120) { out ->
            tvHomeInfo.text = out.ifEmpty { "Restart selesai." }
            refreshStatus()
        }
    }

    private fun showLog() {
        tvHomeInfo.text = "Mengambil log…"
        runDeck("log", 45) { out ->
            tvHomeInfo.text = ""
            val content = tv(out.ifEmpty { "(log kosong)" }, 12f, TXT, mono = true)
            content.setPadding(dp(16), dp(12), dp(16), dp(12))
            val sv = ScrollView(this)
            sv.addView(content)
            AlertDialog.Builder(this)
                .setTitle("Log Stack")
                .setView(sv)
                .setPositiveButton("Tutup", null)
                .show()
        }
    }

    // ===== Tab WebView (Hermes & Router) =====

    private fun buildWebPage(url: String, caption: String, onWeb: (WebView) -> Unit): View {
        val col = LinearLayout(this)
        col.orientation = LinearLayout.VERTICAL
        col.setBackgroundColor(BG)
        val bar = LinearLayout(this)
        bar.orientation = LinearLayout.HORIZONTAL
        bar.setPadding(dp(16), dp(10), dp(16), dp(10))
        val cap = tv(caption, 12f, SUB, mono = true)
        bar.addView(cap, lpWeight())
        val wv = WebView(this)
        onWeb(wv)
        val btnReload = ghostButton("Reload")
        btnReload.textSize = 12f
        btnReload.setOnClickListener { wv.reload() }
        bar.addView(btnReload, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        col.addView(bar)
        wv.settings.javaScriptEnabled = true
        wv.settings.domStorageEnabled = true
        wv.settings.loadWithOverviewMode = true
        wv.settings.useWideViewPort = true
        wv.webViewClient = WebViewClient()
        wv.setBackgroundColor(BG)
        col.addView(wv, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        wv.loadUrl(url)
        return col
    }

    // ===== Tab 3: Konsol =====

    private fun buildConsolePage(): View {
        val col = LinearLayout(this)
        col.orientation = LinearLayout.VERTICAL
        col.setBackgroundColor(BG)
        col.setPadding(dp(16), dp(12), dp(16), dp(12))

        col.addView(tv("Perintah cepat", 12f, SUB, bold = true))
        val chipsRow = LinearLayout(this)
        chipsRow.orientation = LinearLayout.HORIZONTAL
        chipsRow.setPadding(0, dp(8), 0, dp(8))
        val quick = listOf("hermes --version", "hermes status", "df -h", "free -m", "ls /data")
        quick.forEach { cmd ->
            val chip = ghostButton(cmd)
            chip.textSize = 12f
            chip.typeface = Typeface.MONOSPACE
            val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT)
            lp.marginEnd = dp(8)
            chip.setOnClickListener { consoleInput.setText(cmd); consoleInput.setSelection(cmd.length) }
            chipsRow.addView(chip, lp)
        }
        val chipsScroll = HorizontalScrollView(this)
        chipsScroll.isHorizontalScrollBarEnabled = false
        chipsScroll.addView(chipsRow)
        col.addView(chipsScroll)

        val inputRow = LinearLayout(this)
        inputRow.orientation = LinearLayout.HORIZONTAL
        consoleInput = EditText(this)
        consoleInput.hint = "Perintah di Ubuntu proot…"
        consoleInput.setTextColor(TXT)
        consoleInput.setHintTextColor(SUB)
        consoleInput.textSize = 14f
        consoleInput.typeface = Typeface.MONOSPACE
        consoleInput.inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
        consoleInput.setPadding(dp(12), dp(10), dp(12), dp(10))
        consoleInput.background = GradientDrawable().apply {
            cornerRadius = dp(10).toFloat()
            setColor(CARD)
            setStroke(dp(1), BORDER)
        }
        inputRow.addView(consoleInput, lpWeight())
        val btnRun = accentButton("Jalankan")
        val lpRun = LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        lpRun.marginStart = dp(8)
        btnRun.setOnClickListener {
            val cmd = consoleInput.text.toString().trim()
            if (cmd.isNotEmpty()) runConsole(cmd)
        }
        inputRow.addView(btnRun, lpRun)
        col.addView(inputRow)

        consoleOut = LinearLayout(this)
        consoleOut.orientation = LinearLayout.VERTICAL
        consoleOut.setPadding(0, dp(12), 0, dp(12))
        consoleScroll = ScrollView(this)
        consoleScroll.addView(consoleOut, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        col.addView(consoleScroll, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        consoleOut.addView(tv("Output konsol tampil di sini. Perintah berjalan di Ubuntu proot lewat deckctl.", 12f, SUB))
        return col
    }

    private fun runConsole(cmd: String) {
        val block = card()
        block.addView(tv("▸ $cmd", 13f, ACCENT, bold = true, mono = true))
        val outTv = tv("Menjalankan…", 12f, SUB, mono = true)
        outTv.setPadding(0, dp(6), 0, 0)
        outTv.setTextIsSelectable(true)
        block.addView(outTv)
        consoleOut.addView(block)
        consoleScroll.post { consoleScroll.fullScroll(View.FOCUS_DOWN) }
        runDeck("console ${shellQuote(cmd)}", 150) { out ->
            outTv.text = out.ifEmpty { "(tanpa output)" }
            outTv.setTextColor(TXT)
            consoleScroll.post { consoleScroll.fullScroll(View.FOCUS_DOWN) }
        }
    }

    // ===== Tab 5: Berkas AI =====

    private fun joinPath(dir: String, name: String): String =
        if (dir == "." || dir.isEmpty()) name else "$dir/$name"

    private fun parentPath(p: String): String {
        if (p == "." || p.isEmpty()) return "."
        val idx = p.lastIndexOf('/')
        return if (idx < 0) "." else p.substring(0, idx)
    }

    private fun buildFilesPage(): View {
        val col = LinearLayout(this)
        col.orientation = LinearLayout.VERTICAL
        col.setBackgroundColor(BG)
        col.setPadding(dp(16), dp(12), dp(16), dp(12))

        val navRow = LinearLayout(this)
        navRow.orientation = LinearLayout.HORIZONTAL
        val btnUp = ghostButton("↑ Naik")
        btnUp.textSize = 12f
        btnUp.setOnClickListener {
            if (currentPath != ".") loadDir(parentPath(currentPath))
        }
        navRow.addView(btnUp)
        tvPath = tv("/data", 13f, TXT, bold = true, mono = true)
        tvPath.setPadding(dp(12), 0, 0, 0)
        navRow.addView(tvPath, lpWeight())
        val btnRe = ghostButton("Refresh")
        btnRe.textSize = 12f
        btnRe.setOnClickListener { loadDir(currentPath) }
        navRow.addView(btnRe)
        col.addView(navRow)

        val actRow = LinearLayout(this)
        actRow.orientation = LinearLayout.HORIZONTAL
        actRow.setPadding(0, dp(8), 0, 0)
        btnPaste = ghostButton("Tempel di sini")
        btnPaste.textSize = 12f
        btnPaste.setOnClickListener {
            val src = clipboardRel
            if (src == null) {
                toast("Belum ada yang disalin — tekan lama berkas/folder dulu")
            } else {
                toast("Menyalin…")
                runDeck("cp ${shellQuote(src)} ${shellQuote(currentPath)}", 150) { out ->
                    toast(out.lines().firstOrNull { it.isNotBlank() } ?: "Selesai")
                    loadDir(currentPath)
                }
            }
        }
        actRow.addView(btnPaste)
        val btnUpload = ghostButton("Unggah berkas")
        btnUpload.textSize = 12f
        btnUpload.setPadding(dp(10), 0, 0, 0)
        btnUpload.setOnClickListener { startUpload() }
        actRow.addView(btnUpload)
        col.addView(actRow)
        tvClipInfo = tv("Tekan lama berkas/folder untuk menyalin.", 11f, SUB)
        tvClipInfo.setPadding(0, dp(6), 0, 0)
        col.addView(tvClipInfo)
        updatePasteUi()

        fileList = LinearLayout(this)
        fileList.orientation = LinearLayout.VERTICAL
        fileList.setPadding(0, dp(10), 0, dp(10))
        val listScroll = ScrollView(this)
        listScroll.addView(fileList, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        col.addView(listScroll, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))

        val viewerCard = card()
        val vHead = LinearLayout(this)
        vHead.orientation = LinearLayout.HORIZONTAL
        tvFileTitle = tv("Pilih berkas untuk melihat isi", 13f, TXT, bold = true, mono = true)
        vHead.addView(tvFileTitle, lpWeight())
        val btnCopy = ghostButton("Salin")
        btnCopy.textSize = 12f
        btnCopy.setOnClickListener {
            if (currentFileContent.isNotEmpty()) {
                val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                cm.setPrimaryClip(ClipData.newPlainText("berkas", currentFileContent))
                toast("Isi berkas disalin")
            } else toast("Belum ada isi berkas")
        }
        vHead.addView(btnCopy, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        viewerCard.addView(vHead)
        tvFileContent = tv("", 12f, SUB, mono = true)
        tvFileContent.setTextIsSelectable(true)
        fileScroll = ScrollView(this)
        fileScroll.addView(tvFileContent)
        viewerCard.addView(fileScroll, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(180)))
        col.addView(viewerCard)
        return col
    }

    private fun loadDir(path: String) {
        currentPath = path
        tvPath.text = if (path == ".") "/data" else "/data/$path"
        fileList.removeAllViews()
        fileList.addView(tv("Memuat…", 13f, SUB))
        runDeck("ls ${shellQuote(path)}", 45) { out ->
            fileList.removeAllViews()
            if (out.startsWith("ERROR")) {
                fileList.addView(tv(out, 13f, RED, mono = true))
                return@runDeck
            }
            val names = out.lines().map { it.trim() }.filter { it.isNotEmpty() }
            if (names.isEmpty()) {
                fileList.addView(tv("(folder kosong)", 13f, SUB))
                return@runDeck
            }
            val sorted = names.sortedWith(compareBy({ !it.endsWith("/") }, { it.lowercase() }))
            sorted.forEach { name ->
                val isDir = name.endsWith("/")
                val clean = name.removeSuffix("/")
                val row = tv((if (isDir) "▸ " else "· ") + name, 14f, if (isDir) ACCENT else TXT, mono = true)
                row.setPadding(dp(10), dp(11), dp(10), dp(11))
                row.background = GradientDrawable().apply {
                    cornerRadius = dp(8).toFloat()
                    setColor(CARD)
                    setStroke(dp(1), BORDER)
                }
                val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
                lp.setMargins(0, 0, 0, dp(8))
                row.setOnClickListener {
                    if (isDir) loadDir(joinPath(currentPath, clean)) else openFile(clean)
                }
                row.setOnLongClickListener {
                    clipboardRel = joinPath(currentPath, clean)
                    updatePasteUi()
                    toast("Disalin: $clean — buka folder tujuan, ketuk Tempel")
                    true
                }
                fileList.addView(row, lp)
            }
        }
    }

    private fun updatePasteUi() {
        val has = clipboardRel != null
        if (::btnPaste.isInitialized) {
            btnPaste.isEnabled = has
            btnPaste.alpha = if (has) 1f else 0.5f
        }
        if (::tvClipInfo.isInitialized) {
            tvClipInfo.text = clipboardRel?.let { "Siap tempel: /data/$it" }
                ?: "Tekan lama berkas/folder untuk menyalin."
        }
    }

    private fun startUpload() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
        }
        try {
            startActivityForResult(intent, REQ_UPLOAD)
        } catch (e: Exception) {
            toast("Pemilih berkas tidak tersedia: ${e.message}")
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_UPLOAD || resultCode != RESULT_OK) return
        val uri = data?.data ?: return
        val destDir = currentPath
        toast("Mengunggah…")
        pool.execute {
            try {
                var name = "unggahan-${System.currentTimeMillis()}"
                contentResolver.query(uri, null, null, null, null)?.use { c ->
                    val idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (idx >= 0 && c.moveToFirst()) c.getString(idx)?.let { name = it }
                }
                val safeName = name.replace(Regex("[/'\\\\]"), "_")
                val dir = File(filesDir, "uploads").apply { mkdirs() }
                val staging = File(dir, safeName)
                val input = contentResolver.openInputStream(uri)
                    ?: throw IllegalStateException("tidak bisa membuka berkas terpilih")
                input.use { ins -> staging.outputStream().use { out -> ins.copyTo(out) } }
                runDeck("put ${shellQuote(staging.absolutePath)} ${shellQuote(destDir)}", 150) { out ->
                    toast(out.lines().firstOrNull { it.isNotBlank() } ?: "Unggahan selesai")
                    staging.delete()
                    if (currentPath == destDir) loadDir(destDir)
                }
            } catch (e: Exception) {
                mainHandler.post { toast("Unggah gagal: ${e.message}") }
            }
        }
    }

    private fun openFile(name: String) {
        val rel = joinPath(currentPath, name)
        tvFileTitle.text = name
        tvFileContent.text = "Memuat isi…"
        tvFileContent.setTextColor(SUB)
        currentFileContent = ""
        runDeck("cat ${shellQuote(rel)}", 45) { out ->
            currentFileContent = out
            tvFileContent.text = out.ifEmpty { "(berkas kosong)" }
            tvFileContent.setTextColor(TXT)
            fileScroll.post { fileScroll.scrollTo(0, 0) }
        }
    }
}
