struct CleanupPromptExample: Equatable, Sendable {
    let name: String
    let input: String
    let output: String
    let precedingContext: String?

    init(
        name: String,
        input: String,
        output: String,
        precedingContext: String? = nil
    ) {
        self.name = name
        self.input = input
        self.output = output
        self.precedingContext = precedingContext
    }

    static let all: [CleanupPromptExample] = [
        CleanupPromptExample(
            name: "auto-correction",
            input: "on se voit lundi enfin non plutôt mardi à 14 heures",
            output: "On se voit mardi à 14 heures."
        ),
        CleanupPromptExample(
            name: "énumération",
            input: "il faut vérifier le dossier appeler la cliente et envoyer le devis",
            output: "Il faut\u{202F}:\n- vérifier le dossier\u{202F};\n- appeler la cliente\u{202F};\n- envoyer le devis."
        ),
        CleanupPromptExample(
            name: "e-mail",
            input: "bonjour madame martin je vous envoie le devis en pièce jointe cordialement paul",
            output: "Bonjour Madame Martin,\n\nJe vous envoie le devis en pièce jointe.\n\nCordialement,\nPaul"
        ),
        CleanupPromptExample(
            name: "message de chat",
            input: "salut tkt stp envoie moi le devis SFM30 de Prazo Elevator pr demain merci",
            output: "Salut, ne t’inquiète pas. S’il te plaît, envoie-moi le devis SFM30 de Prazo Elevator pour demain. Merci."
        ),
        CleanupPromptExample(
            name: "termes techniques",
            input: "le ticket dicta mac concerne sfm trente et prazo elevator",
            output: "Le ticket DictaMac concerne SFM30 et Prazo Elevator."
        ),
        CleanupPromptExample(
            name: "continuité",
            input: "ce choix est le plus sûr",
            output: "ce choix est le plus sûr.",
            precedingContext: "Je pense que"
        ),
        CleanupPromptExample(
            name: "hésitations et répétitions",
            input: "euh le colis le colis arrive demain à 9 heures",
            output: "Le colis arrive demain à 9 heures."
        )
    ]
}
