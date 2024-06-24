import clsx from 'clsx';
import Heading from '@theme/Heading';
import styles from './styles.module.css';

type FeatureItem = {
  title: string;
  image: string;
  imageType: 'svg' | 'jpg' | 'png';
  description: JSX.Element;
};

const FeatureList: FeatureItem[] = [
  {
    title: 'Plot',
    image: require('@site/static/img/3dplot.png').default,
    imageType: 'png',
    description: (
      <>
        placeholder image stolen from the internet.
      </>
    ),
  },
  {
    title: 'Render',
    image: require('@site/static/img/teapot.png').default,
    imageType: 'png',
    description: (
      <>
        placeholder image stolen from the internet.
      </>
    ),
  },
  {
    title: 'Export',
    image: require('@site/static/img/cube.png').default,
    imageType: 'png',
    description: (
      <>
        placeholder image stolen from the internet.
      </>
    ),
  },
];

function Feature({title, image, imageType, description}: FeatureItem) {
  return (
    <div className={clsx('col col--4')}>
      <div className="text--center">
        {image && (
          <img 
            src={image} 
            className={styles.featureSvg} 
            role="img" 
            alt={title}
          />
        )}
      </div>
      <div className="text--center padding-horiz--md">
        <Heading as="h3">{title}</Heading>
        <p>{description}</p>
      </div>
    </div>
  );
}

export default function HomepageFeatures(): JSX.Element {
  return (
    <section className={styles.features}>
      <div className="container">
        <div className="row">
          {FeatureList.map((props, idx) => (
            <Feature key={idx} {...props} />
          ))}
        </div>
      </div>
    </section>
  );
}
