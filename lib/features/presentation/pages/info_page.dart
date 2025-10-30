import '../../../core/utils/common_imports.dart';
import 'package:cached_network_image/cached_network_image.dart';

class InfoPage extends StatelessWidget {
  const InfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F1E8),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Container(
                  padding: 16.0.paddingAll,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                        bottom:
                            BorderSide(color: Colors.grey.shade400, width: 2)),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        'UPSC TODAY',
                        style: TextStyle(
                          fontFamily: 'serif',
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                          color: Colors.black,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () {
                          Navigator.pushNamed(context, AppRoutes.usersListPage);
                        },
                        icon: const Icon(Icons.support_agent,
                            size: 28, color: Colors.black),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 80),
                    children: _buildAllArticles(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildAllArticles() {
    return [
      _buildHeadlineCard(
        'Breaking: UPSC Civil Services 2025 Notification Released',
        'https://images.unsplash.com/photo-1589829085413-56de8ae18c73?w=800',
        'The Union Public Service Commission has officially released the notification for Civil Services Examination 2025. Application process begins from Feb 15.',
      ),
      _buildSectionDivider('PRELIMS PREPARATION'),
      _buildArticleCard(
          'Daily Current Affairs - January 2025',
          'https://images.unsplash.com/photo-1504711434969-e33886168f5c?w=600',
          'Stay updated with the most important current affairs, national and international news relevant for UPSC aspirants.'),
      _buildArticleCard(
          'Polity: Constitutional Amendments Explained',
          'https://images.unsplash.com/photo-1589994965851-a8f479c573a9?w=600',
          'Deep dive into the recent constitutional amendments and their implications for governance and civil services.'),
      _buildArticleCard(
          'Environment & Ecology: Climate Change Policies',
          'https://images.unsplash.com/photo-1542601906990-b4d3fb778b09?w=600',
          'Comprehensive coverage of environmental issues, climate agreements, and biodiversity conservation initiatives.'),
      _buildArticleCard(
          'Indian Economy: Budget 2025 Analysis',
          'https://images.unsplash.com/photo-1554224155-6726b3ff858f?w=600',
          'Complete breakdown of Union Budget 2025 with focus areas relevant for prelims and mains preparation.'),
      _buildArticleCard(
          'Geography: India Physical Features',
          'https://images.unsplash.com/photo-1526778548025-fa2f459cd5c1?w=600',
          'Master Indian geography with detailed maps, climate zones, and physiographic divisions.'),
      _buildArticleCard(
          'Science & Technology: Space Missions 2025',
          'https://images.unsplash.com/photo-1446776653964-20c1d3a81b06?w=600',
          'Latest updates on ISRO missions, space diplomacy, and technological advancements in aerospace.'),
      _buildArticleCard(
          'History: Modern India Freedom Struggle',
          'https://images.unsplash.com/photo-1461360228754-6e81c478b882?w=600',
          'Comprehensive timeline and analysis of India\'s independence movement and key personalities.'),
      _buildArticleCard(
          'International Relations: India-US Partnership',
          'https://images.unsplash.com/photo-1451187580459-43490279c0fa?w=600',
          'Deep dive into bilateral relations, defense cooperation, and strategic partnerships.'),
      _buildArticleCard(
          'Art & Culture: UNESCO World Heritage Sites',
          'https://images.unsplash.com/photo-1548013146-72479768bada?w=600',
          'Complete list and significance of Indian heritage sites recognized by UNESCO.'),
      _buildArticleCard(
          'Ethics: Case Studies for Mains',
          'https://images.unsplash.com/photo-1450101499163-c8848c66ca85?w=600',
          'Real-world ethical dilemmas and frameworks for answering GS4 questions effectively.'),
      _buildSectionDivider('STRATEGY & GUIDANCE'),
      _buildArticleCard(
          'Topper Interview: AIR 1 Shares Strategy',
          'https://images.unsplash.com/photo-1523240795612-9a054b0db644?w=600',
          'Exclusive insights from the All India Rank 1 holder on preparation techniques, time management, and answer writing.'),
      _buildArticleCard(
          'Optional Subject Analysis: Which to Choose?',
          'https://images.unsplash.com/photo-1434030216411-0b793f4b4173?w=600',
          'Comprehensive analysis of popular optional subjects, success rates, and expert recommendations for 2025.'),
      _buildArticleCard(
          'Time Management: 365 Day Study Plan',
          'https://images.unsplash.com/photo-1501139083538-0139583c060f?w=600',
          'Detailed year-long preparation strategy covering all subjects with monthly milestones.'),
      _buildArticleCard(
          'Note Making Techniques for UPSC',
          'https://images.unsplash.com/photo-1455390582262-044cdead277a?w=600',
          'Effective methods for creating revision notes that stick and enhance retention.'),
      _buildArticleCard(
          'Revision Strategy for Last 30 Days',
          'https://images.unsplash.com/photo-1484480974693-6ca0a78fb36b?w=600',
          'Power-packed revision plan to maximize scores in the final month before exams.'),
      _buildArticleCard(
          'Newspaper Reading: How to Extract Value',
          'https://images.unsplash.com/photo-1504711434969-e33886168f5c?w=600',
          'Proven techniques to read newspapers effectively for current affairs preparation.'),
      _buildArticleCard(
          'Mock Test Analysis: Boosting Your Score',
          'https://images.unsplash.com/photo-1434030216411-0b793f4b4173?w=600',
          'Learn how to analyze mock tests to identify weak areas and improve performance.'),
      _buildArticleCard(
          'Motivation: Staying Consistent for 2 Years',
          'https://images.unsplash.com/photo-1552664730-d307ca884978?w=600',
          'Mental health tips and motivational strategies for the long UPSC preparation journey.'),
      _buildArticleCard(
          'Coaching vs Self Study: What Works?',
          'https://images.unsplash.com/photo-1427504494785-3a9ca7044f45?w=600',
          'Honest comparison of coaching institutes vs self-study approach with success rates.'),
      _buildArticleCard(
          'Answer Writing Practice: Daily Routine',
          'https://images.unsplash.com/photo-1455390582262-044cdead277a?w=600',
          'How to build answer writing skills through consistent daily practice and evaluation.'),
      _buildSectionDivider('MAINS & INTERVIEW'),
      _buildArticleCard(
          'Essay Writing Masterclass for Mains',
          'https://images.unsplash.com/photo-1455390582262-044cdead277a?w=600',
          'Learn the art of crafting high-scoring essays with examples from previous toppers and expert evaluation.'),
      _buildArticleCard(
          'Personality Test: Mock Interview Tips',
          'https://images.unsplash.com/photo-1552664730-d307ca884978?w=600',
          'Crack the UPSC interview round with confidence. DAF preparation, body language, and common questions answered.'),
      _buildArticleCard(
          'GS1 Answer Writing: History & Culture',
          'https://images.unsplash.com/photo-1461360228754-6e81c478b882?w=600',
          'Specialized tips for writing answers in GS1 covering Indian heritage, culture, and world history.'),
      _buildArticleCard(
          'GS2 Governance: Structure & Issues',
          'https://images.unsplash.com/photo-1589994965851-a8f479c573a9?w=600',
          'Master the art of writing governance answers with focus on constitutional provisions and policy analysis.'),
      _buildArticleCard(
          'GS3 Economy: Data Interpretation Skills',
          'https://images.unsplash.com/photo-1554224155-6726b3ff858f?w=600',
          'How to incorporate economic data, graphs, and statistics in mains answers effectively.'),
      _buildArticleCard(
          'GS4 Ethics: Case Study Approach',
          'https://images.unsplash.com/photo-1450101499163-c8848c66ca85?w=600',
          'Framework-based approach to solve ethics case studies with real examples from toppers.'),
      _buildArticleCard(
          'Interview Transcripts: AIR 10-50 Analysis',
          'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?w=600',
          'Read through actual interview transcripts and learn what worked for successful candidates.'),
      _buildArticleCard(
          'DAF Preparation: Making It Interview-Proof',
          'https://images.unsplash.com/photo-1586281380349-632531db7ed4?w=600',
          'How to fill your Detailed Application Form strategically to get favorable questions.'),
      _buildArticleCard(
          'Current Affairs Integration in Mains',
          'https://images.unsplash.com/photo-1504711434969-e33886168f5c?w=600',
          'Techniques to seamlessly blend current affairs into your mains answers for better marks.'),
      _buildArticleCard(
          'Optional: Public Administration Strategy',
          'https://images.unsplash.com/photo-1450101499163-c8848c66ca85?w=600',
          'Complete preparation strategy for Public Administration optional with booklist and resources.'),
      _buildSectionDivider('CURRENT AFFAIRS DEEP DIVE'),
      _buildArticleCard(
          'India-China Border Talks: Recent Developments',
          'https://images.unsplash.com/photo-1451187580459-43490279c0fa?w=600',
          'Analysis of ongoing border negotiations and implications for bilateral relations.'),
      _buildArticleCard(
          'Digital India: Recent Policy Updates',
          'https://images.unsplash.com/photo-1526374965328-7f61d4dc18c5?w=600',
          'Coverage of latest digital initiatives, cybersecurity laws, and e-governance measures.'),
      _buildArticleCard(
          'Agricultural Reforms: MSP & Policy Changes',
          'https://images.unsplash.com/photo-1625246333195-78d9c38ad449?w=600',
          'Comprehensive analysis of agricultural policies, MSP debates, and farmer welfare schemes.'),
      _buildArticleCard(
          'Healthcare: National Health Mission Updates',
          'https://images.unsplash.com/photo-1576091160399-112ba8d25d1d?w=600',
          'Latest developments in public health infrastructure and universal healthcare initiatives.'),
      _buildArticleCard(
          'Education Policy: NEP 2020 Implementation',
          'https://images.unsplash.com/photo-1523240795612-9a054b0db644?w=600',
          'Current status of National Education Policy implementation across states.'),
      _buildArticleCard(
          'Climate Action: India\'s Net Zero Commitment',
          'https://images.unsplash.com/photo-1542601906990-b4d3fb778b09?w=600',
          'Progress on India\'s climate targets, renewable energy push, and green hydrogen mission.'),
      _buildArticleCard(
          'Women Empowerment: Recent Legislations',
          'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?w=600',
          'Analysis of new laws and policies aimed at women\'s safety, rights, and economic participation.'),
      _buildArticleCard(
          'Space Diplomacy: India\'s Growing Influence',
          'https://images.unsplash.com/photo-1446776653964-20c1d3a81b06?w=600',
          'How India is leveraging space capabilities for diplomatic and strategic gains.'),
      _buildArticleCard(
          'Financial Inclusion: Jan Dhan to Digital Banking',
          'https://images.unsplash.com/photo-1554224155-6726b3ff858f?w=600',
          'Journey of financial inclusion initiatives and their impact on Indian economy.'),
      _buildArticleCard(
          'Smart Cities Mission: Progress Report 2025',
          'https://images.unsplash.com/photo-1449824913935-59a10b8d2000?w=600',
          'Assessment of smart city projects, challenges faced, and future roadmap.'),
      _buildSectionDivider('SUBJECT WISE PREPARATION'),
      _buildArticleCard(
          'Ancient India: Indus Valley to Mauryas',
          'https://images.unsplash.com/photo-1461360228754-6e81c478b882?w=600',
          'Complete coverage of ancient Indian history with archaeological evidences and sources.'),
      _buildArticleCard(
          'Medieval India: Delhi Sultanate Architecture',
          'https://images.unsplash.com/photo-1548013146-72479768bada?w=600',
          'Art and architecture of medieval period with focus on Indo-Islamic synthesis.'),
      _buildArticleCard(
          'World History: World Wars & Cold War',
          'https://images.unsplash.com/photo-1461360228754-6e81c478b882?w=600',
          'Impact of 20th century global conflicts on modern international relations.'),
      _buildArticleCard(
          'Indian Polity: Parliamentary System Analysis',
          'https://images.unsplash.com/photo-1589994965851-a8f479c573a9?w=600',
          'Functioning of Indian Parliament, legislative process, and accountability mechanisms.'),
      _buildArticleCard(
          'Public Administration: Bureaucracy in India',
          'https://images.unsplash.com/photo-1450101499163-c8848c66ca85?w=600',
          'Role of civil services, administrative reforms, and challenges in governance.'),
      _buildArticleCard(
          'Indian Economy: Monetary Policy Framework',
          'https://images.unsplash.com/photo-1554224155-6726b3ff858f?w=600',
          'Understanding RBI policies, inflation targeting, and banking sector reforms.'),
      _buildArticleCard(
          'Security Issues: Internal & External Threats',
          'https://images.unsplash.com/photo-1451187580459-43490279c0fa?w=600',
          'Analysis of terrorism, naxalism, cyber threats, and border security challenges.'),
      _buildArticleCard(
          'Disaster Management: Recent Case Studies',
          'https://images.unsplash.com/photo-1547683905-f686c993aae5?w=600',
          'Learning from recent natural disasters and effectiveness of response mechanisms.'),
      const SizedBox(height: 80),
    ];
  }

  Widget _buildHeadlineCard(String title, String imageUrl, String description) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black, width: 3),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(2, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CachedNetworkImage(
            imageUrl: imageUrl,
            height: 200,
            width: double.infinity,
            fit: BoxFit.cover,
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
            placeholder: (_, __) => Image.asset(
              'assets/logo.jpg',
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
            errorWidget: (_, __, ___) => Image.asset(
              'assets/logo.jpg',
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'serif',
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: const TextStyle(
                      fontSize: 14, color: Colors.black, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArticleCard(String title, String imageUrl, String description) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade400, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CachedNetworkImage(
            imageUrl: imageUrl,
            width: 100,
            height: 100,
            fit: BoxFit.cover,
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
            placeholder: (_, __) => Image.asset(
              'assets/logo.jpg',
              width: 100,
              height: 100,
              fit: BoxFit.cover,
            ),
            errorWidget: (_, __, ___) => Image.asset(
              'assets/logo.jpg',
              width: 100,
              height: 100,
              fit: BoxFit.cover,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'serif',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                      color: Colors.black,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.black, height: 1.4),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionDivider(String title) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border(
          top: BorderSide(color: Colors.grey.shade400, width: 1),
          bottom: BorderSide(color: Colors.grey.shade400, width: 1),
        ),
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: 'serif',
          fontSize: 14,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}
