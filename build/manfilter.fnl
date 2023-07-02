(local {:text pdtext :path pdpath :utils pdutils &as pd} (require :pandoc))

(local debug? (or (os.getenv :MAN_PANDOC_DEBUG) true))
(fn d [msg]
  (when debug? (io.stderr:write (: "%s\n" :format msg)))
  nil)

(local (basename ext) (-?> PANDOC_STATE.output_file
                           (pdpath.filename)
                           (pdpath.split_extension)))

;; nils left in for documentation purposes - they'll be set later
(local new-meta {:date (os.date "%Y-%m-%d")
                 :header nil
                 :section (-?> ext (: :match "^%.([0-9])$"))
                 :title nil})

(fn get-meta-header-and-title [meta]
  ;; saving off values for later manipulation
  (when meta.header (set new-meta.header meta.header))
  (if meta.title (set new-meta.title meta.title)
      basename (set new-meta.title basename))
  nil)

(fn Meta [meta]
  "Set all manpage metadata not specified by --metadata foo=x"
  (each [k v (pairs new-meta)]
    (when (= nil (. meta k))
      (d (: "Setting metadata '%s' to '%s' for manpage '%s'" :format k v
            PANDOC_STATE.output_file))
      (tset meta k v)))
  meta)

(fn Header [el]
  "Save first H1 for setting meta.header, replace with NAME
NAME's contents are set to '<meta.title> - <original H1 contents>"
  (if (= el.level 1)
      (when (not new-meta.header)
        (assert new-meta.title "meta.title not set")
        (set new-meta.header (pdutils.stringify el.content))
        (d (: "Setting meta.header from first H1; adding NAME from meta.title: '%s - %s'"
              :format new-meta.title new-meta.header))
        [(pd.Header 1 (pd.Str :NAME))
         (pd.Para (pd.Inlines (pd.Str (.. new-meta.title " - " new-meta.header))))
         (pd.Header 1 (pd.Str :DESCRIPTION))])
      (doto el
        (tset :level (math.max 1 (- el.level 1))))))

(fn h1-upper [el]
  "Convert all level-1 headers to uppercase"
  (when (= 1 el.level)
    (pd.walk_block el {:Str (fn [el] (pd.Str (pdtext.upper el.text)))})))

(fn Table [el]
  "Format markdown tables into manpage-friendly format (not supported by pandoc)"
  (d (.. "formatting table for " PANDOC_STATE.output_file))
  (let [rendered (pd.write (pd.Pandoc [el]) :plain)
        adjusted (-> rendered
                     (: :gsub "%+([=:][=:]+)"
                        #(.. " " (string.rep "-" (- (length $) 1))))
                     (: :gsub "(%+[-:][-:]+)" "")
                     (: :gsub "%+\n" "\n")
                     (: :gsub "\n|    " "\n|")
                     (: :gsub "|" ""))]
    [(pd.RawBlock :man ".RS -14n")
     (pd.CodeBlock adjusted)
     (pd.RawBlock :man :.RE)]))

;; TODO: process footnotes for output to manpage
;; by default, they don't appear to be emitted even without a blank Note
; (fn Note [el] {})

[{:Meta get-meta-header-and-title}
 {: Header}
 {:Header h1-upper}
 {: Table}
 {: Meta}]

