package org.trailbound.core.route

/**
 * The Walk for Freedom catalogue. Only routes with geometry ([route] != null) are walkable; the rest are shown
 * greyed out as teasers, and every card opens a detail page with [facts] so people learn something either way.
 * Facts stick to well-documented history; all copy is DRAFT pending historian review, and living people get no
 * likeness (see README risk register, P3).
 */
data class Journey(
    val id: String,
    val title: String,
    val subtitle: String,
    val km: Int,
    val postcards: Int,
    val teaser: String,
    /** How it unlocks, shown on the locked card. */
    val unlock: String,
    val route: Route? = null,
    /** Timeline / key facts for the detail page, oldest first. */
    val facts: List<String> = emptyList(),
    /** One line on why it belongs in VeilWalker. */
    val why: String = "",
    /** Set for Outlaws on Foot collectibles: unlocked by lifetime steps instead of a route. */
    val card: OutlawCard? = null,
)

object Journeys {
    val all: List<Journey> get() = freedom + Outlaws.all

    /** Walk for Freedom routes; the outlaw cards come after, as the endgame past the Silk Road. */
    private val freedom: List<Journey> = listOf(
        Journey(
            "north-star-1", NorthStarRoute.title, NorthStarRoute.subtitle,
            km = (NorthStarRoute.lengthM / 1000).toInt(), postcards = NorthStarRoute.milestones.size,
            teaser = "Harriet Tubman's corridor north through the Delmarva Peninsula.",
            unlock = "active", route = NorthStarRoute,
            facts = listOf(
                "c. 1822: Araminta Ross is born into slavery in Dorchester County, Maryland.",
                "1849: She escapes alone, following the North Star, and takes the name Harriet Tubman.",
                "1850s: She returns about 13 times and guides roughly 70 people to freedom.",
                "1863: She leads the Combahee River Raid in the Civil War, freeing more than 700 people.",
            ),
            why = "The original act of walking toward freedom, at night, unseen.",
        ),
        Journey(
            "north-star-2", "The North Star", "Chapter 2 · Philadelphia to St. Catharines",
            km = 700, postcards = 14,
            teaser = "Through New York to Canada, where Tubman settled the families she led to freedom.",
            unlock = "finish North Star I",
            facts = listOf(
                "1850: The Fugitive Slave Act makes freedom seekers unsafe anywhere in the US.",
                "1851–1858: Tubman bases herself in St. Catharines, Ontario, beyond US law.",
                "Routes ran through New York State, often via Rochester, to the Niagara crossing.",
            ),
            why = "When the law follows you, keep walking until it can't.",
        ),
        Journey(
            "silk-road", "The Silk Road", "Chang'an to Constantinople · the real distance",
            km = 6400, postcards = 24,
            teaser = "About 6,400 km of caravan routes that carried silk, paper, religions and ideas between China and the Mediterranean.",
            unlock = "coming soon",
            facts = listOf(
                "c. 138–126 BCE: Han envoy Zhang Qian's missions west open the routes to China's court.",
                "Goods moved in relays; few traders ever walked the whole way.",
                "Paper, papermaking and Buddhism travelled it; so did the plague in the 1300s.",
                "1877: German geographer Ferdinand von Richthofen coins the name \"Silk Road\".",
            ),
            why = "The longest walk on the list, measured at its real-world length.",
        ),
        Journey(
            "douglass", "Disguised as a Sailor", "Frederick Douglass · Baltimore to New York, 1838",
            km = 300, postcards = 8,
            teaser = "Borrowed papers, a sailor's clothes, one train ride. He became the century's great voice against slavery.",
            unlock = "coming soon",
            facts = listOf(
                "Sept 3, 1838: Dressed as a sailor, carrying a free Black seaman's papers, he boards a train in Baltimore.",
                "By train and steamboat via Wilmington and Philadelphia, he reaches New York in under 24 hours.",
                "Anna Murray, who helped fund the escape, joins him; they marry days later.",
                "1845: He publishes his Narrative, an instant bestseller.",
            ),
            why = "Courage plus a convincing disguise: an early lesson in operational security.",
        ),
        Journey(
            "selma", "Bloody Sunday to the Capitol", "Selma to Montgomery, 1965",
            km = 87, postcards = 9,
            teaser = "Turned back on the Edmund Pettus Bridge, the marchers came back and walked all 87 km for the vote.",
            unlock = "coming soon",
            facts = listOf(
                "Mar 7, 1965: State troopers attack marchers on the Edmund Pettus Bridge (\"Bloody Sunday\").",
                "Mar 21–25: Thousands walk 54 miles (87 km) from Selma to the Alabama Capitol.",
                "Aug 6, 1965: The Voting Rights Act is signed into law.",
            ),
            why = "A walk that changed the law.",
        ),
        Journey(
            "lovelace", "The Enchantress of Numbers", "Ada Lovelace · London",
            km = 50, postcards = 7,
            teaser = "In 1843 she published the first algorithm meant for a machine, a century before computers existed.",
            unlock = "coming soon",
            facts = listOf(
                "1815: Born Augusta Ada Byron, daughter of the poet Lord Byron.",
                "1843: Her Notes on Babbage's Analytical Engine include \"Note G\", a method for computing Bernoulli numbers.",
                "She saw that such a machine could work with symbols, music even, not just numbers.",
            ),
            why = "Every app, this one included, descends from her notes.",
        ),
        Journey(
            "hopper", "Amazing Grace", "Grace Hopper · Harvard to the Pentagon",
            km = 700, postcards = 8,
            teaser = "She built the first compiler and taught computers to read something close to English.",
            unlock = "coming soon",
            facts = listOf(
                "1947: Her team tapes a moth into the Harvard Mark II log: the \"first actual case of bug being found\".",
                "1952: She builds the A-0, one of the first compilers.",
                "1959: Her work leads to COBOL, still running banks today.",
            ),
            why = "Making machines speak human was its own kind of liberation.",
        ),
        Journey(
            "turing", "Breaking Enigma", "Alan Turing · Bletchley Park to Manchester",
            km = 250, postcards = 10,
            teaser = "He cracked the codes that shortened a war and wrote the theory every computer runs on.",
            unlock = "coming soon",
            facts = listOf(
                "1936: \"On Computable Numbers\" defines the universal machine.",
                "1939–1945: At Bletchley Park his Bombe design helps break German Enigma traffic.",
                "1952: Prosecuted for homosexuality; he dies in 1954. Royal pardon in 2013.",
            ),
            why = "The father of computer science, persecuted for his private life.",
        ),
        Journey(
            "phreaks", "The 2600 Hz Whistle", "Phone phreaks · \"Captain Crunch\"",
            km = 40, postcards = 6,
            teaser = "A toy whistle from a cereal box could seize the phone network. Hacking culture starts here.",
            unlock = "coming soon",
            facts = listOf(
                "1960s: Phreaks discover the network's 2600 Hz control tone; a Cap'n Crunch prize whistle can play it.",
                "John Draper takes the nickname \"Captain Crunch\".",
                "1971: Steve Wozniak and Steve Jobs build and sell \"blue boxes\" before founding Apple.",
            ),
            why = "Curiosity about how systems really work: the root of hacker culture.",
        ),
        Journey(
            "diffie-hellman", "New Directions", "Whitfield Diffie & Martin Hellman · Stanford, 1976",
            km = 30, postcards = 6,
            teaser = "Two strangers can agree on a secret in public. Their paper made private internet traffic possible.",
            unlock = "coming soon",
            facts = listOf(
                "1976: \"New Directions in Cryptography\" introduces public-key key exchange.",
                "Ralph Merkle's earlier work on public key distribution fed into the same idea.",
                "2015: Diffie and Hellman receive the Turing Award.",
            ),
            why = "Every padlock in your browser, and your phone talking to us over Tor, starts here.",
        ),
        Journey(
            "rsa", "We Got Him?", "Rivest, Shamir & Adleman · MIT, 1977",
            km = 45, postcards = 7,
            teaser = "Three researchers found the first practical public-key cipher. A British spy had found it first, in secret.",
            unlock = "coming soon",
            facts = listOf(
                "1973: At GCHQ, Clifford Cocks devises the same idea; it stays classified until 1997.",
                "1977: Rivest, Shamir and Adleman publish RSA at MIT.",
                "1977: Martin Gardner's Scientific American column sets the RSA-129 challenge.",
                "1994: RSA-129 falls to volunteers worldwide: \"The Magic Words Are Squeamish Ossifrage\".",
            ),
            why = "Public math versus secret math, and the public won the credit.",
        ),
        Journey(
            "pgp", "Pretty Good Privacy", "Phil Zimmermann · 1991",
            km = 60, postcards = 6,
            teaser = "He gave the world strong encryption for free, and was investigated for 'exporting munitions' for it.",
            unlock = "coming soon",
            facts = listOf(
                "1991: Zimmermann releases PGP; it spreads worldwide over the internet.",
                "1993–1996: US authorities investigate him for exporting cryptography; the case is dropped.",
                "1995: PGP's source code is published as a printed book, protected as speech, to get it abroad.",
            ),
            why = "Privacy for everyone, not just governments.",
        ),
        Journey(
            "cypherpunks", "Cypherpunks Write Code", "The cypherpunk mailing list · 1992",
            km = 35, postcards = 6,
            teaser = "A mailing list of cryptographers decided privacy wouldn't be granted, it would be built.",
            unlock = "coming soon",
            facts = listOf(
                "1992: Eric Hughes, Timothy C. May and John Gilmore start the cypherpunks list.",
                "1993: Hughes writes \"A Cypherpunk's Manifesto\": \"Cypherpunks write code.\"",
                "The list incubates anonymous remailers, digital cash and early Tor-era ideas.",
            ),
            why = "VeilWalker's whole philosophy in one sentence.",
        ),
        Journey(
            "cdc", "The Dead Cow Walk", "Cult of the Dead Cow · Lubbock to DEF CON",
            km = 1100, postcards = 8,
            teaser = "Texas teenagers founded a hacker collective that gave the world Back Orifice and the word \"hacktivism\".",
            unlock = "coming soon",
            facts = listOf(
                "1984: cDc is founded in Lubbock, Texas.",
                "1996: cDc member Omega coins \"hacktivism\".",
                "1998: Back Orifice is unveiled at DEF CON 6 to expose Windows security flaws.",
            ),
            why = "Hacking as protest and as public-interest security research.",
        ),
        Journey(
            "condor", "The Condor", "Kevin Mitnick · a DEF CON walk",
            km = 15, postcards = 6,
            teaser = "Once the most wanted computer hacker in America, later the person companies paid to break in.",
            unlock = "coming soon",
            facts = listOf(
                "Best known for social engineering: talking people out of passwords and access.",
                "Feb 1995: Arrested in Raleigh, North Carolina after years as a fugitive; \"Free Kevin\" campaigns follow.",
                "2000: Released; he becomes a security consultant and author (Ghost in the Wires, 2011).",
                "2023: Dies in July.",
            ),
            why = "The human is usually the weakest link. Guard your 24 words.",
        ),
        Journey(
            "chanology", "We Are Legion", "Anonymous · Project Chanology, 2008",
            km = 20, postcards = 6,
            teaser = "An imageboard in-joke turned into a global street protest behind Guy Fawkes masks.",
            unlock = "coming soon",
            facts = listOf(
                "Mid-2000s: Anonymous emerges from the 4chan imageboard culture.",
                "Jan 2008: The Church of Scientology moves to suppress a leaked Tom Cruise video; Anonymous responds.",
                "Feb 10, 2008: Project Chanology street protests in cities worldwide; Guy Fawkes masks become the symbol.",
            ),
            why = "The first time an anonymous online collective walked into the streets.",
        ),
        Journey(
            "genesis", "The Genesis Block", "Satoshi Nakamoto · 21 km for 21 million",
            km = 21, postcards = 7,
            teaser = "A pseudonymous author published nine pages, mined block zero, then vanished.",
            unlock = "coming soon",
            facts = listOf(
                "Oct 31, 2008: The Bitcoin whitepaper is posted to a cryptography mailing list.",
                "Jan 3, 2009: The genesis block embeds a headline: \"Chancellor on brink of second bailout for banks\".",
                "2011: Satoshi's last known messages; the author's identity remains unknown.",
                "The supply is capped at 21 million coins, hence the 21 km.",
            ),
            why = "Proof that a pseudonym can change the world. VeilWalker's ledger is built the same chained, signed way.",
        ),
        Journey(
            "mauerweg", "The Wall Trail", "Berlin · 1961–1989",
            km = 160, postcards = 12,
            teaser = "Walk the line where the Berlin Wall stood, past the places people risked everything to cross.",
            unlock = "coming soon",
            facts = listOf(
                "Aug 13, 1961: The Wall goes up overnight around West Berlin.",
                "At least 140 people are killed at the Wall trying to cross or in connection with it.",
                "Nov 9, 1989: The Wall opens. Today the Mauerweg trail follows its path.",
            ),
            why = "A border built to stop people walking, and the day they walked through it.",
        ),
        Journey(
            "whistleblower", "The Whistleblower Trail", "Hong Kong · June 2013",
            km = 40, postcards = 6,
            teaser = "A contractor walked out with proof of mass surveillance and changed how the world thinks about privacy.",
            unlock = "coming soon",
            facts = listOf(
                "June 2013: In Hong Kong, NSA contractor Edward Snowden gives journalists documents on mass surveillance.",
                "Reporting reveals programs such as PRISM and bulk phone-record collection.",
                "2015: The USA FREEDOM Act ends bulk collection of Americans' phone records by the NSA.",
            ),
            why = "Why Tor-by-default matters.",
        ),
        Journey(
            "motorcycle", "The Motorcycle Diaries", "Che Guevara · Buenos Aires to Caracas, 1952",
            km = 8000, postcards = 20,
            teaser = "The journey across South America that turned a medical student into a revolutionary. Told honestly, controversies included.",
            unlock = "coming soon",
            facts = listOf(
                "1952: Ernesto Guevara and Alberto Granado ride a 1939 Norton (\"La Poderosa\") north from Argentina.",
                "The poverty he saw on the road shaped his politics.",
                "Later a leader of the Cuban Revolution; he oversaw executions at La Cabaña prison, which critics condemn.",
                "1967: Captured and executed in Bolivia. Admired by some, condemned by others.",
            ),
            why = "A journey that changed a person; history shown with its contradictions.",
        ),
    )

    val active: Journey get() = all.first { it.route != null }
    val locked: List<Journey> get() = all.filter { it.route == null }
    val outlaws: List<Journey> get() = Outlaws.all
    fun byId(id: String): Journey? = all.firstOrNull { it.id == id }
}
