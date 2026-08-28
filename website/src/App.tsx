import Hero from './components/Hero';
import Story from './components/Story';
import MacDemo from './components/MacDemo';
import Showcase from './components/Showcase';
import Playground from './components/Playground';
import Pairing from './components/Pairing';
import Download from './components/Download';
import Footer from './components/Footer';

export default function App() {
  return (
    <>
      <Hero />
      <main>
        <Story />
        <MacDemo />
        <Showcase />
        <Playground />
        <Pairing />
        <Download />
      </main>
      <Footer />
    </>
  );
}
